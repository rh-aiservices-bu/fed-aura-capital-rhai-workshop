"""Make instructor 1.3.2's Mode.JSON_SCHEMA emit real OpenAI structured outputs.

Stock 1.3.2 turns Mode.JSON_SCHEMA into response_format={"type":"json_object",
"schema": ...}. The "schema" sibling is not part of the OpenAI API and both OpenAI
and vLLM ignore it, so the schema is never enforced and a model is free to answer
`{}`. instructor 1.3.2 predates structured outputs, so no stock mode sends the
correct wire format. Patch it, then assert the result.
"""
import pathlib
import re

TARGET = pathlib.Path(
    "/opt/app-root/lib64/python3.12/site-packages/instructor/process_response.py"
)

PATTERN = re.compile(
    r'elif mode == Mode\.JSON_SCHEMA:\n'
    r'(\s+)new_kwargs\["response_format"\] = \{\n'
    r'\s+"type": "json_object",\n'
    r'\s+"schema": response_model\.model_json_schema\(\),\n'
    r'\s+\}'
)


def _replacement(match: "re.Match[str]") -> str:
    indent = match.group(1)
    return (
        "elif mode == Mode.JSON_SCHEMA:\n"
        f'{indent}new_kwargs["response_format"] = {{\n'
        f'{indent}    "type": "json_schema",\n'
        f'{indent}    "json_schema": {{\n'
        f'{indent}        "name": response_model.__name__,\n'
        f'{indent}        "schema": response_model.model_json_schema(),\n'
        f'{indent}        "strict": True,\n'
        f'{indent}    }},\n'
        f'{indent}}}'
    )


source = TARGET.read_text()
patched, count = PATTERN.subn(_replacement, source)
if count != 1:
    raise SystemExit(
        f"refusing to continue: expected exactly 1 Mode.JSON_SCHEMA branch, found {count}. "
        "The base image's instructor version probably changed - re-check by hand."
    )
TARGET.write_text(patched)
print(f"instructor: patched {count} Mode.JSON_SCHEMA branch")

# Functional assertion - verify the wire format, not just the text edit.
from pydantic import BaseModel  # noqa: E402
from instructor.process_response import handle_response_model  # noqa: E402
from instructor.mode import Mode  # noqa: E402


class _Probe(BaseModel):
    x: int


result = handle_response_model(
    _Probe, mode=Mode.JSON_SCHEMA, messages=[{"role": "user", "content": "hi"}]
)
kwargs = result[1] if isinstance(result, tuple) else result
response_format = kwargs["response_format"]
assert response_format["type"] == "json_schema", response_format
assert response_format["json_schema"]["strict"] is True, response_format
assert (
    response_format["json_schema"]["schema"]["properties"]["x"]["type"] == "integer"
), response_format
print(
    "instructor: response_format ->",
    response_format["type"],
    "| strict:",
    response_format["json_schema"]["strict"],
)
