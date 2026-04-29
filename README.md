# galaxio-template-registry

Default template registry for `galaxio-cli`.

The registry points the CLI to public template packs. It does not contain the
templates themselves.

## Registry

The root manifest is [`galaxio-registry.yaml`](galaxio-registry.yaml).

```yaml
apiVersion: galaxio.io/v1
kind: TemplateRegistry
packs:
  - name: gatling
    source: github:galax-io/templates-gatling
    description: Gatling performance testing templates
```

## Packs

| Name | Source | Description |
| --- | --- | --- |
| `gatling` | `github:galax-io/templates-gatling` | Gatling performance testing templates |
