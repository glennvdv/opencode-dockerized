#!/bin/bash

# Bash completion for opencode-dockerized.sh
# Source this file in your ~/.bashrc or install system-wide

_opencode_dockerized() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="run auth models exec mcp plugin stats debug build update version config clean help --help -h"

    case "${prev}" in
        run|models)
            # Complete directory paths for run command
            mapfile -t COMPREPLY < <(compgen -d -- "${cur}")
            return 0
            ;;
        config)
            # Complete config subcommands
            mapfile -t COMPREPLY < <(compgen -W "show edit path" -- "${cur}")
            return 0
            ;;
        mcp)
            mapfile -t COMPREPLY < <(compgen -W "list add auth logout" -- "${cur}")
            return 0
            ;;
        plugin)
            mapfile -t COMPREPLY < <(compgen -W "list add check update remove" -- "${cur}")
            return 0
            ;;
        debug)
            mapfile -t COMPREPLY < <(compgen -W "paths config agents" -- "${cur}")
            return 0
            ;;
        *)
            ;;
    esac

    if [ "${COMP_WORDS[1]}" = "stats" ] && [ "${COMP_CWORD}" -gt 1 ]; then
        mapfile -t COMPREPLY < <(compgen -W "--days --year --all --project --models --tools --cost --full --limit --json" -- "${cur}")
        return 0
    fi

    mapfile -t COMPREPLY < <(compgen -W "${opts}" -- "${cur}")
    return 0
}

complete -F _opencode_dockerized opencode-dockerized.sh
complete -F _opencode_dockerized ./opencode-dockerized.sh
complete -F _opencode_dockerized opencode-dockerized
complete -F _opencode_dockerized ocd
