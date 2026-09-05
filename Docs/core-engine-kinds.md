# Which transformer kinds a build contains

`TransformerKind.selectable` lists the kinds compiled into this binary, and
`EngineConfiguration.resolvedTransformerPreference` filters a stored preference through
it. Without that filter a preference naming an engine the binary does not contain is
silently dropped at routing time, so the configuration says one thing and the product
does another.

- `.cloud` is compiled in only under `UTTRFLOW_CLOUD`. The app does not define it, so the
  shipped binary contains no path that reaches the network from the dictation pipeline.
- `.localModel` is compiled in only under `UTTRFLOW_LOCAL_MODEL`. The app does not define
  it either: `UttrflowLocalModel` links MLX, whose Metal shaders need a toolchain the app
  deliberately does not require in order to build. The bake-off reaches it and measures
  it; the app does not.
- Apple's Foundation Models handle Hindi. This is undocumented but verified, so the
  language the local model was brought in for is covered without it.
