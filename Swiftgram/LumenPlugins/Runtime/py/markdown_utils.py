# exteraGram markdown_utils: turns markdown into plain text plus entities.
import re


class RawEntity(object):
    def __init__(self, type, offset, length, url=None, language=None, document_id=None):
        self.type = type
        self.offset = offset
        self.length = length
        self.url = url
        self.language = language
        self.document_id = document_id

    def to_tlrpc_object(self):
        return self


class ParsedMessage(object):
    def __init__(self, text, entities):
        self.text = text
        self.entities = entities


_PATTERNS = [
    ("pre", re.compile(r"```(?:(\w+)\n)?([\s\S]+?)```")),
    ("code", re.compile(r"`([^`\n]+)`")),
    ("bold", re.compile(r"\*\*([\s\S]+?)\*\*")),
    ("underline", re.compile(r"__([\s\S]+?)__")),
    ("strikethrough", re.compile(r"~~([\s\S]+?)~~")),
    ("spoiler", re.compile(r"\|\|([\s\S]+?)\|\|")),
    ("italic", re.compile(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])")),
    ("text_link", re.compile(r"\[([^\]]+)\]\(([^)\s]+)\)")),
]


def parse_markdown(text, *args, **kwargs):
    text = "" if text is None else str(text)
    entities = []
    changed = True
    while changed:
        changed = False
        for kind, pattern in _PATTERNS:
            match = pattern.search(text)
            if match is None:
                continue
            if kind == "pre":
                inner = match.group(2)
                language = match.group(1)
                url = None
            elif kind == "text_link":
                inner = match.group(1)
                language = None
                url = match.group(2)
            else:
                inner = match.group(1)
                language = None
                url = None
            start = match.start()
            text = text[:start] + inner + text[match.end():]
            entities.append(RawEntity(kind, start, len(inner), url=url, language=language))
            changed = True
            break
    return ParsedMessage(text, entities)
