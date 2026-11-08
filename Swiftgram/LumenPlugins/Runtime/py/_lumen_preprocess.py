# Source fixes applied to a plugin before Skulpt compiles it.
#
# Skulpt ignores decorators on generator functions (`@contextmanager def f(): yield`), so
# those are rewritten to the equivalent assignment after the function: `f = deco(f)`.
# Line numbers after the function are kept the same.
import re

_DEF = re.compile(r"^([ \t]*)(?:async[ \t]+)?def[ \t]+([A-Za-z_]\w*)[ \t]*\(")
_YIELD = re.compile(r"\byield\b")


def _indent(line):
    return len(line) - len(line.lstrip(" \t"))


def _triple_quotes(line):
    return line.count('"""') + line.count("'''")


def fix_generator_decorators(source):
    lines = source.split("\n")
    out = []
    i = 0
    count = len(lines)
    while i < count:
        line = lines[i]
        stripped = line.strip()
        if not stripped.startswith("@"):
            out.append(line)
            i += 1
            continue
        # A run of single-line decorators directly above a def.
        decorators = []
        j = i
        while j < count and lines[j].strip().startswith("@") and lines[j].count("(") == lines[j].count(")"):
            decorators.append(lines[j].strip()[1:].strip())
            j += 1
        match = _DEF.match(lines[j]) if j < count else None
        if not decorators or match is None:
            out.append(line)
            i += 1
            continue
        def_indent = len(match.group(1))
        name = match.group(2)
        # Find the end of the function body, minding triple-quoted strings.
        k = j + 1
        in_string = _triple_quotes(lines[j]) % 2 == 1
        is_generator = False
        while k < count:
            body = lines[k]
            if in_string:
                if _triple_quotes(body) % 2 == 1:
                    in_string = False
                k += 1
                continue
            text = body.strip()
            if text and not text.startswith("#") and _indent(body) <= def_indent:
                break
            if _YIELD.search(body):
                is_generator = True
            if _triple_quotes(body) % 2 == 1:
                in_string = True
            k += 1
        if not is_generator:
            out.extend(lines[i:j])
            i = j
            continue
        expression = name
        for decorator in reversed(decorators):
            expression = decorator + "(" + expression + ")"
        out.extend(lines[j:k])
        out.append(" " * def_indent + name + " = " + expression)
        out.extend([""] * (len(decorators) - 1))
        i = k
    return "\n".join(out)


_CLASS = re.compile(r"^([ \t]*)class[ \t]+([A-Za-z_]\w*)")
_DEF_ARGS = re.compile(r"^([ \t]*)(?:async[ \t]+)?def[ \t]+[A-Za-z_]\w*[ \t]*\(\s*([A-Za-z_]\w*)?")


def fix_zero_arg_super(source):
    """Skulpt's zero-argument super() fails in classes declared inside functions, so every
    `super()` becomes `super(Class, self)` using the enclosing class and method."""
    if "super()" not in source:
        return source
    lines = source.split("\n")
    stack = []  # (indent, kind, value)
    in_string = False
    for index, line in enumerate(lines):
        if in_string:
            if _triple_quotes(line) % 2 == 1:
                in_string = False
            continue
        text = line.strip()
        if not text or text.startswith("#"):
            continue
        indent = _indent(line)
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if "super()" in line:
            method_arg = None
            class_name = None
            for entry_indent, kind, value in reversed(stack):
                if kind == "def" and method_arg is None:
                    method_arg = value
                elif kind == "class" and method_arg is not None:
                    class_name = value
                    break
            if class_name and method_arg:
                lines[index] = line.replace("super()", "super(" + class_name + ", " + method_arg + ")")
        match = _CLASS.match(line)
        if match:
            stack.append((indent, "class", match.group(2)))
        else:
            match = _DEF_ARGS.match(line)
            if match:
                stack.append((indent, "def", match.group(2)))
        if _triple_quotes(line) % 2 == 1:
            in_string = True
    return "\n".join(lines)


def prepare(source):
    return fix_zero_arg_super(fix_generator_decorators(source))
