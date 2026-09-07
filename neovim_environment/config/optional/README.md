# Optional config

Files here are **not** loaded. Copy one into `lua/plugins/` to enable it.

## `lsp-quiet.lua`

basedpyright's default `typeCheckingMode` is `"recommended"`, which its own
documentation describes as essentially `"all"`. Against a scientific stack
where scikit-learn, OpenCV and TensorFlow ship no types, that reports several
hundred "this is untyped" diagnostics per file — none of which describes a
defect in your code.

This file sets `"standard"` and silences the untyped-third-party rules while
keeping `reportUndefinedVariable`, `reportUnboundVariable` and
`reportSelfClsParameterName` at error.

Enable globally:

```bash
cp optional/lsp-quiet.lua ~/.config/nvim/lua/plugins/lsp.lua
```

Disable again:

```bash
rm ~/.config/nvim/lua/plugins/lsp.lua
```

Per project instead, which overrides whatever the editor sends — see
`../../python_environment/config/pyproject.template.toml`.
