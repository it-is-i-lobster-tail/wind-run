"""Add fields required by WindRun's models to a cktool Development export."""

import json
import re
import sys
from pathlib import Path


IDENTIFIER = r'(?:"[A-Za-z_][A-Za-z_0-9]*"|[A-Za-z_][A-Za-z_0-9]*)'
RECORD = re.compile(rf"\bRECORD\s+TYPE\s+(?P<name>{IDENTIFIER})\s*\((?P<body>[^()]*)\)\s*;")
FIELD = re.compile(
    rf"(?:^|,)\s*(?P<name>{IDENTIFIER})\s+"
    r"(?P<type>ENCRYPTED\s+[A-Z0-9]+|LIST\s*<\s*[A-Z0-9]+\s*>|"
    r"NUMBER\s+PREFERRED\s+AS\s+(?:INT64|DOUBLE)|[A-Z0-9]+)(?=\s|,|$)"
)


def merge_schema(schema, required):
    if not re.match(r"\s*DEFINE\s+SCHEMA\b", schema):
        raise ValueError("Expected a CloudKit schema exported by cktool")
    remaining = dict(required)

    def update_record(match):
        name = match["name"].strip('"')
        if name not in remaining:
            return match[0]

        body = match["body"]
        existing = {field["name"].strip('"'): field["type"] for field in FIELD.finditer(body)}
        additions = []
        for key, definition in sorted(remaining.pop(name).items()):
            expected = definition.removesuffix(" QUERYABLE")
            actual = existing.get(key)
            if actual is None:
                additions.append(f'        "{key}" {definition}')
                continue
            actual = " ".join(actual.split()).removeprefix("NUMBER PREFERRED AS ")
            if actual != expected and not (actual == "NUMBER" and expected in {"INT64", "DOUBLE"}):
                raise ValueError(f"{name}.{key} is {actual} in CloudKit and {expected} in SwiftData")

        if not additions:
            return match[0]
        # Keep existing fields, indexes and grants byte-for-byte. Append new fields to the record.
        prefix = match[0][:match.start("body") - match.start()]
        suffix = match[0][match.end("body") - match.start():]
        separator = ",\n" if body.strip() else "\n"
        return prefix + body.rstrip() + separator + ",\n".join(additions) + "\n    " + suffix

    updated, parsed_records = RECORD.subn(update_record, schema)
    if len(re.findall(r"\bRECORD\s+TYPE\b", schema)) != parsed_records:
        raise ValueError("Could not read every record type in the CloudKit export")

    for name, fields in sorted(remaining.items()):
        definitions = ['        "___recordID" REFERENCE QUERYABLE']
        definitions.extend(f'        "{key}" {definition}' for key, definition in sorted(fields.items()))
        updated = updated.rstrip() + f'\n\n    RECORD TYPE "{name}" (\n' + ",\n".join(definitions) + "\n    );\n"
    return updated


if __name__ == "__main__":
    existing, model_fields, output = map(Path, sys.argv[1:])
    try:
        merged = merge_schema(existing.read_text(), json.loads(model_fields.read_text()))
    except ValueError as error:
        sys.exit(f"CloudKit schema: {error}")
    output.write_text(merged)
