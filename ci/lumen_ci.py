#!/usr/bin/env python3
"""Builds an unsigned-for-distribution Lumen IPA on a macOS GitHub runner.

There are no Apple certificates or provisioning profiles in CI: Bazel signing is
disabled, and every bundle is then ad-hoc signed with the entitlements that
re-signing tools (SideStore, AltStore, Sideloadly, Feather) read from the binary.
The installer replaces the signature with the user's own free Apple ID.
"""
import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

DEFAULT_BUNDLE_ID = 'com.artem.lumen'
# Placeholder team; the re-signing tool substitutes the real one.
DEFAULT_TEAM_ID = 'LUMEN00000'
# Notification extensions are useless without push (unavailable to free Apple IDs);
# Siri intents and screen broadcast are rarely used. Each extension costs an App ID.
DEFAULT_EXTENSIONS = 'ShareExtension,WidgetExtension'

PROFILE_GUARD = ('    if platform_prerequisites.platform.is_device:\n'
                 '        processor_partials.append(\n'
                 '            partials.provisioning_profile_partial(')

BAZELRC_EXTRA = '''
# Lumen unsigned CI settings (temporary, restored after the build)
build --action_env=PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
build --//Telegram:disableProvisioningProfiles=true
build --features=disable_legacy_signing
# Survive transient GitHub 504s while Bazel fetches its own rule archives.
common --experimental_repository_downloader_retries=5
build --jobs={jobs}
build --worker_max_instances=SwiftCompile=1
build --experimental_ui_max_stdouterr_bytes=-1
build --@build_bazel_rules_swift//swift:copt=-no-warnings-as-errors
'''

_NOISE = re.compile(r'^\S+:\d+:\d+: (warning|note|remark): ')
_PROGRESS = re.compile(r'^\[[\d,]+ / [\d,]+\] ')


def run(args, cwd=None, capture=False):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout


def run_filtered(args, cwd):
    """Warnings from this build run to megabytes; keep errors, Bazel messages and
    one progress line a minute so the log stays readable and the runner alive."""
    import time
    print('+ ' + ' '.join(map(str, args)), flush=True)
    process = subprocess.Popen(list(map(str, args)), cwd=cwd, text=True, errors='replace',
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    quiet, last = False, 0.0
    for line in process.stdout:
        if _NOISE.match(line):
            quiet = True
            continue
        if quiet and (line[:1] in (' ', '\t', '|') or not line.strip()):
            continue
        quiet = False
        if _PROGRESS.match(line):
            if time.monotonic() - last < 60:
                continue
            last = time.monotonic()
        print(line, end='', flush=True)
    if process.wait() != 0:
        subprocess.run(['df', '-h', str(cwd)])
        raise subprocess.CalledProcessError(process.returncode, args)


def configuration(env):
    api_id = env.get('TELEGRAM_API_ID', '').strip()
    api_hash = env.get('TELEGRAM_API_HASH', '').strip()
    bundle_id = env.get('APP_BUNDLE_ID', '').strip() or DEFAULT_BUNDLE_ID
    team_id = env.get('APPLE_TEAM_ID', '').strip() or DEFAULT_TEAM_ID
    # Never print the values themselves: they come from repository secrets.
    if not re.fullmatch(r'[1-9][0-9]{0,9}', api_id) or int(api_id) > 2147483647:
        raise ValueError('TELEGRAM_API_ID secret is missing or malformed')
    if not re.fullmatch(r'[0-9a-fA-F]{32}', api_hash):
        raise ValueError('TELEGRAM_API_HASH secret is missing or malformed')
    if not re.fullmatch(r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+', bundle_id):
        raise ValueError('APP_BUNDLE_ID is malformed')
    if not re.fullmatch(r'[A-Z0-9]{10}', team_id):
        raise ValueError('APPLE_TEAM_ID is malformed')
    return {
        'bundle_id': bundle_id, 'api_id': api_id, 'api_hash': api_hash, 'team_id': team_id,
        'app_center_id': '0', 'is_internal_build': 'true', 'is_appstore_build': 'false',
        'appstore_id': '0', 'app_specific_url_scheme': 'tg', 'premium_iap_product_id': '',
        'enable_siri': False, 'enable_icloud': False, 'sg_config': '',
    }


def verify_ipa(path, bundle_id):
    with zipfile.ZipFile(path) as archive:
        if archive.testzip():
            raise ValueError('Corrupt IPA')
        mains = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(mains) != 1:
            raise ValueError('IPA must contain exactly one application')
        info = plistlib.loads(archive.read(mains[0]))
        if info.get('CFBundleIdentifier') != bundle_id:
            raise ValueError('Unexpected bundle identifier ' + str(info.get('CFBundleIdentifier')))
        if 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
            raise ValueError('Not a device build')
        executable = mains[0].rsplit('/', 1)[0] + '/' + info['CFBundleExecutable']
        if archive.getinfo(executable).file_size == 0:
            raise ValueError('Empty application executable')
        return {k: info.get(k) for k in ('CFBundleIdentifier', 'CFBundleDisplayName',
                                         'CFBundleShortVersionString', 'CFBundleVersion')}


def _sign(path, work, entitlements=None):
    args = ['codesign', '--force', '--sign', '-', '--timestamp=none']
    if entitlements is not None:
        file = work / (path.name + '.entitlements')
        file.write_bytes(plistlib.dumps(entitlements))
        args += ['--entitlements', file, '--generate-entitlement-der']
    run(args + [path])


def embed_sideload_entitlements(ipa, team_id, keep_extensions):
    """Without an app group in the binaries the installer never registers one, and
    the app and its extensions cannot share the account database.

    A free Apple ID registers at most 10 App IDs a week and every extension takes one,
    so only the extensions in keep_extensions stay in the IPA."""
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        root = work / 'ipa'
        run(['ditto', '-x', '-k', ipa, root])
        app = next((root / 'Payload').glob('*.app'))
        bundle_id = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
        group = 'group.' + bundle_id

        def entitlements(identifier):
            return {'application-identifier': team_id + '.' + identifier,
                    'com.apple.developer.team-identifier': team_id,
                    'com.apple.security.application-groups': [group]}

        for plugin in (app / 'PlugIns').glob('*.appex'):
            if not any(plugin.stem.startswith(name) for name in keep_extensions):
                print('Removing extension ' + plugin.name, flush=True)
                shutil.rmtree(plugin)
        nested = [p for p in app.rglob('*') if p.suffix == '.framework' or (p.suffix == '.dylib' and p.is_file())]
        # Deepest first, so each container is signed after the code inside it.
        for code in sorted(nested, key=lambda p: len(p.parts), reverse=True):
            _sign(code, work)
        plugins = sorted((app / 'PlugIns').glob('*.appex'))
        for plugin in plugins:
            plugin_id = plistlib.loads((plugin / 'Info.plist').read_bytes())['CFBundleIdentifier']
            _sign(plugin, work, entitlements(plugin_id))
        _sign(app, work, entitlements(bundle_id))
        rebuilt = work / 'rebuilt.ipa'
        run(['ditto', '-c', '-k', '--norsrc', root, rebuilt])
        shutil.copyfile(rebuilt, ipa)
        return [p.name for p in plugins]


def build(source, output, env):
    if sys.platform != 'darwin':
        raise RuntimeError('The iOS build needs a macOS runner with Xcode')
    build_config = env.get('LUMEN_CONFIGURATION', 'release_arm64')
    if build_config not in ('release_arm64', 'debug_arm64'):
        raise ValueError('Unknown configuration ' + build_config)
    config = configuration(env)
    versions = json.loads((source / 'versions.json').read_text())
    xcode = run(['xcodebuild', '-version'], capture=True).strip()
    if xcode.splitlines()[0] != 'Xcode ' + versions['xcode']:
        raise ValueError('Selected ' + xcode.splitlines()[0] + ', versions.json wants ' + versions['xcode'])

    output.mkdir(parents=True, exist_ok=True)
    build_input = source / 'build-input'
    build_input.mkdir(exist_ok=True)
    config_path = build_input / 'lumen-ci-configuration.json'
    rc_path = source / '.bazelrc'
    rules_path = source / 'build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl'
    original_rc, original_rules = rc_path.read_bytes(), rules_path.read_bytes()
    number = 100000 + int(env.get('GITHUB_RUN_NUMBER', '1')) * 10 + int(env.get('GITHUB_RUN_ATTEMPT', '1'))
    manifest = {'configuration': build_config, 'xcode': xcode, 'versions': versions,
                'build_number': number, 'bundle_id': config['bundle_id'], 'status': 'running'}
    try:
        # rules_apple embeds a provisioning profile into every device bundle regardless
        # of disable_legacy_signing; gate that step so the unsigned build can finish.
        rules = original_rules.decode('utf-8')
        guards = rules.count(PROFILE_GUARD)
        if guards == 0:
            raise ValueError('rules_apple provisioning guard not found; the patch needs updating')
        rules_path.write_text(rules.replace(PROFILE_GUARD, PROFILE_GUARD.replace(
            'platform.is_device:', 'platform.is_device and "disable_legacy_signing" not in features:')),
            encoding='utf-8')
        print('Patched %d rules_apple provisioning guards' % guards, flush=True)

        config_path.write_text(json.dumps(config), encoding='utf-8')
        config_path.chmod(0o600)
        rc_path.write_bytes(original_rc + BAZELRC_EXTRA.format(jobs=env.get('LUMEN_JOBS', '3')).encode())

        sys.path.insert(0, str(source / 'build-system/Make'))
        from BazelLocation import locate_bazel, calculate_sha256
        os.chdir(source)
        expected_version, expected_hash = versions['bazel'].split(':', 1)
        # Fetch the Bazel binary ourselves, with hard retries: GitHub's release CDN returns
        # transient 504s, and locate_bazel's own curl writes the error body instead of failing.
        bazel_name = 'bazel-{}-darwin-arm64'.format(expected_version)
        bazel_target = build_input / bazel_name
        import time as _time
        if not bazel_target.is_file() or calculate_sha256(str(bazel_target)) != expected_hash:
            url = 'https://github.com/bazelbuild/bazel/releases/download/{}/{}'.format(expected_version, bazel_name)
            for attempt in range(1, 7):
                print('+ downloading %s (attempt %d)' % (bazel_name, attempt), flush=True)
                subprocess.run(['curl', '-fL', '--retry', '6', '--retry-all-errors', '--retry-delay', '15',
                                '--connect-timeout', '30', '-o', str(bazel_target), url], check=False)
                if bazel_target.is_file() and calculate_sha256(str(bazel_target)) == expected_hash:
                    bazel_target.chmod(0o755)
                    break
                print('Bazel download attempt %d failed, retrying' % attempt, flush=True)
                bazel_target.unlink(missing_ok=True)
                _time.sleep(20)
            else:
                raise RuntimeError('Could not download Bazel after retries (GitHub 504?)')
        bazel = Path(locate_bazel(str(source), None, None))
        if calculate_sha256(str(bazel)) != expected_hash:
            raise ValueError('Downloaded Bazel does not match versions.json')
        manifest['bazel'] = run([bazel, '--version'], capture=True).strip()

        make = [sys.executable, '-u', 'build-system/Make/Make.py', '--bazel=' + str(bazel)]
        if env.get('LUMEN_BAZEL_CACHE'):
            make.append('--cacheDir=' + env['LUMEN_BAZEL_CACHE'])
        common = ['--configurationPath=' + str(config_path), '--xcodeManagedCodesigning',
                  '--buildNumber=' + str(number)]
        run(make + ['generateProject'] + common + ['--disableProvisioningProfiles'], cwd=source)
        run_filtered(make + ['build', '--continueOnError'] + common + ['--configuration=' + build_config], cwd=source)

        ipa = source / 'bazel-bin/Telegram/Swiftgram.ipa'
        if not ipa.is_file():
            raise FileNotFoundError('Make.py finished but Swiftgram.ipa is missing')
        verify_ipa(ipa, config['bundle_id'])
        target = output / 'Lumen-{}.ipa'.format(number)
        shutil.copyfile(ipa, target)
        keep = [name.strip() for name in env.get('LUMEN_EXTENSIONS', DEFAULT_EXTENSIONS).split(',') if name.strip()]
        manifest['extensions'] = embed_sideload_entitlements(target, config['team_id'], keep)
        manifest['app'] = verify_ipa(target, config['bundle_id'])
        manifest['ipa'] = target.name
        manifest['status'] = 'success'
        print('Built ' + target.name, flush=True)
    except BaseException as error:
        manifest['status'] = 'failed'
        manifest['failure'] = type(error).__name__
        raise
    finally:
        rules_path.write_bytes(original_rules)
        rc_path.write_bytes(original_rc)
        config_path.unlink(missing_ok=True)
        (output / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path('artifacts'))
    args = parser.parse_args()
    build(args.source.resolve(), args.output.resolve(), os.environ)
