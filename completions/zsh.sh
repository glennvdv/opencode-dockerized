#compdef opencode-dockerized.sh
# shellcheck shell=bash disable=SC2034,SC2154,SC1087,SC2016

# Zsh completion for opencode-dockerized.sh
# Source this file in your ~/.zshrc or place in /usr/local/share/zsh/site-functions/

_opencode_dockerized() {
    local -a commands
    commands=(
        'run:Run OpenCode in Docker (default: current directory)'
        'auth:Run OpenCode authentication (opencode auth login)'
        'models:List models available to the configured providers'
        'exec:Run a non-interactive prompt (opencode run)'
        'mcp:Manage MCP servers'
        'plugin:Manage plugins'
        'stats:Show usage statistics'
        'debug:Debugging and troubleshooting tools'
        'build:Build the Docker image'
        'update:Update OpenCode to the latest version'
        'version:Show OpenCode version in the container'
        'config:Show, edit, or print config file path'
        'clean:Remove the Docker image'
        'help:Show help message'
    )

    _arguments -C \
        '1: :->cmds' \
        '*:: :->args'

    case $state in
        cmds)
            _describe -t commands 'opencode-dockerized command' commands
            ;;
        args)
            case $words[1] in
                run|models)
                    _files -/
                    ;;
                mcp)
                    _values 'mcp subcommand' list add auth logout
                    ;;
                plugin)
                    _values 'plugin subcommand' list add check update remove
                    ;;
                debug)
                    _values 'debug subcommand' paths config agents
                    ;;
                stats)
                    _arguments \
                        '--days[Show the last N days; 0 means today]:days:' \
                        '--year[Show a calendar year]:year:' \
                        '--all[Show lifetime statistics]' \
                        '--project[Filter by project ID, or "." for the current project]:project:' \
                        '--models[Show model usage]' \
                        '--tools[Show tool reliability]' \
                        '--cost[Show cost and token details]' \
                        '--full[Show every detailed section]' \
                        '--limit[Number of rows in detailed sections]:limit:' \
                        '--json[Output statistics as JSON]'
                    ;;
                config)
                    local -a config_cmds
                    config_cmds=(
                        'show:Show current configuration'
                        'edit:Edit config file in $EDITOR'
                        'path:Print config file path'
                    )
                    _describe -t config_cmds 'config subcommand' config_cmds
                    ;;
            esac
            ;;
    esac
}

compdef _opencode_dockerized opencode-dockerized.sh
compdef _opencode_dockerized opencode-dockerized
compdef _opencode_dockerized ocd
