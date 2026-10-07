"""Write JSON the way Qt's QJsonDocument::Indented does (Mudlet's saveJsonMap),
so a rewritten map file only differs where its content changed."""
import json

_ESCAPES = {'"': '\\"', "\\": "\\\\", "\b": "\\b", "\f": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t"}


def _string(value):
    out = ['"']
    for ch in value:
        if ch in _ESCAPES:
            out.append(_ESCAPES[ch])
        elif ord(ch) < 0x20:
            out.append("\\u%04x" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def _scalar(value):
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "null"
    if isinstance(value, str):
        return _string(value)
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return json.dumps(value)


def _write(value, level, out):
    pad = "    " * level
    inner = "    " * (level + 1)
    if isinstance(value, dict):
        out.append("{\n")
        keys = sorted(value)
        for index, key in enumerate(keys):
            out.append(inner + _string(key) + ": ")
            _write(value[key], level + 1, out)
            out.append(",\n" if index < len(keys) - 1 else "\n")
        out.append(pad + "}")
    elif isinstance(value, list):
        out.append("[\n")
        for index, item in enumerate(value):
            out.append(inner)
            _write(item, level + 1, out)
            out.append(",\n" if index < len(value) - 1 else "\n")
        out.append(pad + "]")
    else:
        out.append(_scalar(value))


def dumps(value):
    out = []
    _write(value, 0, out)
    out.append("\n")
    return "".join(out)
