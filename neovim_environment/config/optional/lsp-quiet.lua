-- LSP settings.
--
-- LazyVim's Python extra selects basedpyright but passes no `settings` block,
-- so the server runs on its own defaults. basedpyright's default
-- typeCheckingMode is "recommended", which its documentation describes as
-- essentially the same as "all": reportAny, reportUnknownMemberType,
-- reportMissingTypeStubs and friends are all errors. Against TensorFlow,
-- scikit-learn and OpenCV — none of which ship complete types — that buries
-- real diagnostics under thousands of "this is untyped" reports and reads as
-- "autocomplete is broken".
--
-- These settings are the editor-side default. A project's pyproject.toml
-- (see python_environment/config/pyproject.template.toml) overrides them and
-- is what the CLI, pre-commit and CI read.

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              -- Ruff and isort own import ordering via conform. Leaving this
              -- enabled means two tools rewrite imports on the same buffer.
              disableOrganizeImports = true,
              analysis = {
                typeCheckingMode = "standard",

                -- "openFilesOnly" keeps a large repo responsive. Switch to
                -- "workspace" for a project-wide sweep, at the cost of a full
                -- re-analysis on every change.
                diagnosticMode = "openFilesOnly",

                -- The setting that actually produces completion for untyped
                -- but readable libraries: sklearn, cv2, xgboost, dvc, mlflow.
                -- Without it those modules are Unknown and offer nothing.
                useLibraryCodeForTypes = true,

                autoSearchPaths = true,
                autoImportCompletions = true,

                inlayHints = {
                  variableTypes = true,
                  callArgumentNames = true,
                  functionReturnTypes = true,
                  genericTypes = false,
                },

                diagnosticSeverityOverrides = {
                  -- Every rule below fires only because third-party scientific
                  -- libraries are untyped. None of them describes a defect in
                  -- your code.
                  reportMissingTypeStubs = "none",
                  reportUnknownMemberType = "none",
                  reportUnknownVariableType = "none",
                  reportUnknownArgumentType = "none",
                  reportUnknownParameterType = "none",
                  reportUnknownLambdaType = "none",
                  reportAny = "none",
                  reportExplicitAny = "none",
                  reportUnusedCallResult = "none",
                  reportPrivateImportUsage = "none",
                  -- Keep the ones that catch real bugs loud.
                  reportUndefinedVariable = "error",
                  reportSelfClsParameterName = "error",
                  reportUnboundVariable = "error",
                },
              },
            },
          },
        },
      },
    },
  },
}
