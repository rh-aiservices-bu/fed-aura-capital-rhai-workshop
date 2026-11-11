# EvalHub Ragas adapter, patched so structured output is actually schema-enforced.
# ragas 0.4.3 asks for instructor Mode.JSON, and instructor 1.3.2 turns BOTH Mode.JSON and
# Mode.JSON_SCHEMA into response_format={"type":"json_object"}
#
# Build (--platform matters: an arm64 build will not run on the cluster), then push:
#   podman build --platform linux/amd64 -t quay.io/rh-aiservices-bu/community-ragas:custom-v2 -f ragas-adapter.Containerfile .
#   podman push quay.io/rh-aiservices-bu/community-ragas:custom-v2
# Wire up: set lmEvalImagePatcher.ragasImage in the EvalHub chart - its patcher Job and
# enforcer CronJob rewrite the provider configmaps the TrustyAI operator keeps reverting.
# Use a NEW tag per build: the provider config sets no imagePullPolicy, so an overwritten
# tag can be served from node cache and you silently keep running the old adapter.

FROM quay.io/evalhub/community-ragas:v0.7.2

USER 0

ARG RAGAS_BASE=/opt/app-root/lib64/python3.12/site-packages/ragas/llms/base.py

# Patch 1 - ragas: ask for the schema-enforcing mode.
RUN set -eux; \
    test -f "$RAGAS_BASE"; \
    before="$(grep -c 'Mode\.JSON\b' "$RAGAS_BASE" || true)"; \
    test "$before" -gt 0; \
    sed -i 's/Mode\.JSON\b/Mode.JSON_SCHEMA/g' "$RAGAS_BASE"; \
    test "$(grep -c 'Mode\.JSON\b' "$RAGAS_BASE" || true)" -eq 0; \
    echo "ragas: patched $before occurrence(s) Mode.JSON -> Mode.JSON_SCHEMA"

# Patch 2 - instructor: emit OpenAI structured outputs instead of json_object. The script
# asserts the resulting wire format, so a silent miss fails the build instead of shipping
# an image indistinguishable from upstream that fails identically at runtime.
COPY instructor-json-schema.patch.py /tmp/instructor-json-schema.patch.py
RUN set -eux; \
    python /tmp/instructor-json-schema.patch.py; \
    rm -f /tmp/instructor-json-schema.patch.py

USER 1001
