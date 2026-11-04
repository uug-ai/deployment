# Self-hosted with Docker Compose

....

## Agent HTTP port migration

This Docker Compose guide is not yet complete. For Agent installation and
configuration, see the [Agent guide](https://learn.uug.ai/docs/agent/) and
[Agent README](https://github.com/kerberos-io/agent#readme).

Docker mappings use `HOST_PORT:CONTAINER_PORT`. Published Agent releases still
listen on container port `80`. With `AGENT_IMAGE` set to a verified tag or digest
for one of those releases, expose the UI at `http://localhost:8080` with:

```bash
docker run --name kerberos-agent -p 8080:80 \
  "${AGENT_IMAGE:?Set AGENT_IMAGE to a verified port-80 Agent image}"
```

The forthcoming hardened Agent image instead listens on container port `8080`.
Only after that image is available, set `AGENT_IMAGE` to its verified tag or
digest and use:

```bash
docker run --name kerberos-agent -p 8080:8080 \
  "${AGENT_IMAGE:?Set AGENT_IMAGE to a verified port-8080 Agent image}"
```

These are alternative commands for a new container, not an in-place upgrade.
Preserve your existing environment variables, mounts and recordings when
recreating a container. In Compose, the equivalent `ports` entry changes from
`"8080:80"` to `"8080:8080"` together with the image. Your chosen host port and
browser URL need not change. Do not apply the new mapping to legacy images,
or assume `kerberos/agent:latest` already includes the hardening update.
