load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "LumenPlugins",
    module_name = "LumenPlugins",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        # "-warnings-as-errors",
    ],
    deps = [
        "//Swiftgram/SGSimpleSettings:SGSimpleSettings",
        "//Swiftgram/SGSwiftUI:SGSwiftUI",
        "//submodules/Display:Display",
        "//submodules/LegacyUI:LegacyUI",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
    ],
    visibility = [
        "//visibility:public",
    ],
)
