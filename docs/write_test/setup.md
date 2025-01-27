# Development setup

This document describes the existing developer tooling we have in place (and
what to expect of it).

- [Environment Setup](#environment-setup)
  - [Visual Studio Code](#visual-studio-code)
  - [Emacs](#emacs)
  - [Other setups](#other-setups)
- [Code checks](#code-checks)
- [Extended reading](#extended-reading)

## Environment Setup

Follow the [installation](../quick_start#installation) steps to prepare the
source code. Then follow the steps below to set up the corresponding development
environment.

### Visual Studio Code

1. Click on the Python version at the bottom left of the editor's window and
   select the Python interpreter which Poetry just created. If you do not find
   it, check [FAQ and troubleshooting](../troubleshooting.md) for extra
   instructions. This step is important because it ensures that the current
   workspace uses the correct Poetry virtual environment which provides all
   dependencies required.

1. You can copy the settings below into `.vscode/settings.json`.

    ```json
    {
        "markdown.extension.toc.levels": "2..6",
        "python.analysis.typeCheckingMode": "strict",
        "python.formatting.provider": "black",
        "python.linting.enabled": true,
        "python.linting.flake8Enabled": true,
        "python.linting.mypyEnabled": true,
        "python.linting.pylintEnabled": false,
        "editor.formatOnSave": true,
        "python.linting.mypyArgs": [
            "--strict",
            "--namespace-packages",
            "--implicit-reexport",
            "--show-column-numbers"
        ],
        "python.sortImports.path": "isort",
        "python.analysis.useLibraryCodeForTypes": false,
        "python.analysis.autoImportCompletions": false,
        "files.eol": "\n",
        "terminal.integrated.env.windows": {
            "mypypath": "${workspaceFolder}\\typings"
        },
        "python.analysis.diagnosticSeverityOverrides": {
            "reportUntypedClassDecorator": "none",
            "reportUnknownMemberType": "none",
            "reportGeneralTypeIssues": "none",
            "reportUnknownVariableType": "none",
            "reportUnknownArgumentType": "none",
            "reportUnknownParameterType": "none",
            "reportUnboundVariable": "none",
            "reportPrivateUsage": "none",
            "reportImportCycles": "none",
            "reportUnnecessaryIsInstance": "none",
        },
        "python.languageServer": "Pylance",
        "markdown.extension.toc.levels": "2..6",
    }
    ```

1. Install extensions.

   - Install
     [Pylance](https://marketplace.visualstudio.com/items?itemName=ms-python.vscode-pylance)
     to get best code intelligence experience.
   - Install
     [Rewrap](https://marketplace.visualstudio.com/items?itemName=stkb.rewrap)
     to automatically wrap.
   - If there is need to update the documentation, it is recommended to install
     [Markdown All in
     One](https://marketplace.visualstudio.com/items?itemName=yzhang.markdown-all-in-one).
     It helps to maintain the table of contents in the documentation.

### Emacs

Use the [pyvenv](https://github.com/jorgenschaefer/pyvenv) package:

```emacs-lisp
(use-package pyvenv
  :ensure t
  :hook (python-mode . pyvenv-tracking-mode))
```

Then run `M-x add-dir-local-variable RET python-mode RET pyvenv-activate RET
<path/to/virtualenv>` where the value is the path given by the command above.
This will create a `.dir-locals.el` file as follows:

```emacs-lisp
;;; Directory Local Variables
;;; For more information see (info "(emacs) Directory Variables")

((python-mode . ((pyvenv-activate . "~/.cache/pypoetry/virtualenvs/lisa-s7Q404Ij-py3.8"))))
```

### Other setups

- Install and enable [ShellCheck](https://github.com/koalaman/shellcheck) to
  find bash errors locally.

## Code checks

If the development environment is set up correctly, the following tools will
automatically check the code. If there is any problem with the development
environment settings, please feel free to submit an issue to us or create a pull
request for repair. You can also run the check manually.

- [Black](https://github.com/psf/black), the opinionated code formatter resolves
  all disputes about how to format our Python files. This will become clearer
  after following [PEP 8](https://www.python.org/dev/peps/pep-0008/) (official
  Python style guide).
- [Flake8](https://flake8.pycqa.org/en/latest/) (and integrations), the semantic
  analyzer, used to coordinate most other tools.
- [isort](https://timothycrosley.github.io/isort/), the `import` sorter, it will
  automatically divide the import into the expected alphabetical order.
- [mypy](http://mypy-lang.org/), the static type checker, which allows us to
  find potential errors by annotating and checking types.
- [rope](https://github.com/python-rope/rope), provides completion and renaming
  support for pyls.

## Extended reading

- [Python Design Patterns](https://python-patterns.guide/). A fantastic
  collection of material for using Python's design patterns.
- [The Hitchhiker’s Guide to Python](https://docs.python-guide.org/). This
  handcrafted guide exists to provide both novice and expert Python developers a
  best practice handbook for the installation, configuration, and usage of
  Python on a daily basis.
- LISA performs static type checking to help finding bugs. Learn more from [mypy
  cheat sheet](https://mypy.readthedocs.io/en/latest/cheat_sheet_py3.html) and
  [typing lib](https://docs.python.org/3/library/typing.html). You can also
  learn from LISA code.
- [How to write best commit
  messages](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html)
  and [Git best
  practice](http://sethrobertson.github.io/GitBestPractices/#sausage).
