# Simpl
# by Eduardo Ruiz
# https://github.com/eduarbo/simpl
# MIT License

# Simpl theme heavily inspired by Sindre Sorhus' Pure theme
# https://github.com/sindresorhus/pure

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# Configuration
# Set options in the SIMPL namespace to not pollute the global namespace

: ${SIMPL_ALWAYS_SHOW_USER:=0}
: ${SIMPL_ALWAYS_SHOW_USER_AND_HOST:=0}
: ${SIMPL_CMD_MAX_EXEC_TIME:=5}
: ${SIMPL_ENABLE_RPROMPT:=0}
: ${SIMPL_GIT_DELAY_DIRTY_CHECK:=1800}
: ${SIMPL_GIT_PULL:=1}
: ${SIMPL_GIT_UNTRACKED_DIRTY:=1}

# symbols
: ${SIMPL_GIT_DIRTY_SYMBOL:="*"}
: ${SIMPL_GIT_DOWN_ARROW:="⇣"}
: ${SIMPL_GIT_UP_ARROW:="⇡"}
: ${SIMPL_GIT_STASH_SYMBOL:="≡"}
: ${SIMPL_JOBS_SYMBOL:="↻"}
: ${SIMPL_SUSPENDED_JOBS_SYMBOL:="✦"}
: ${SIMPL_PROMPT_ROOT_SYMBOL:="#"}
: ${SIMPL_PROMPT_SYMBOL:="❱"}
: ${SIMPL_PROMPT_VICMD_SYMBOL:="❰"}

# colors
: ${SIMPL_DIR_COLOR:="%F{cyan}"}
: ${SIMPL_EXEC_TIME_COLOR:="%B%F{8}"}
: ${SIMPL_GIT_ACTION_COLOR:="%F{yellow}"}
: ${SIMPL_GIT_ARROW_COLOR:="%B%F{blue}"}
: ${SIMPL_GIT_BRANCH_COLOR:="%F{14}"}
: ${SIMPL_GIT_BRANCH_CACHED_COLOR:="%F{red}"}
: ${SIMPL_GIT_DIRTY_COLOR:="%F{9}"}
: ${SIMPL_GIT_STASH_COLOR:="%F{cyan}"}
: ${SIMPL_HOST_COLOR:="%F{11}"}
: ${SIMPL_HOST_SYMBOL_COLOR:="%F{yellow}"}
: ${SIMPL_JOBS_COLOR:="%B%F{8}"}
: ${SIMPL_PREPOSITION_COLOR:="%F{8}"}
: ${SIMPL_PROMPT_SYMBOL_COLOR:="%F{yellow}"}
: ${SIMPL_PROMPT_SYMBOL_ERROR_COLOR:="%F{red}"}
: ${SIMPL_PROMPT2_SYMBOL_COLOR:="%F{8}"}
: ${SIMPL_SUSPENDED_JOBS_COLOR:="%F{red}"}
: ${SIMPL_USER_COLOR:="%F{11}"}
: ${SIMPL_USER_ROOT_COLOR:="%B%F{red}"}
: ${SIMPL_VENV_COLOR:="%F{11}"}

# Formatting reset sequence, namespaced to avoid polluting the global scope.
typeset -g prompt_simpl_reset="%f%s%u%k%b"

_prompt_simpl_human_time_to_var() {
	local human total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	typeset -g "${var}"="${human}"
}

_prompt_simpl_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_simpl_cmd_timestamp:-$EPOCHSECONDS} ))
	typeset -g prompt_simpl_cmd_exec_time=
	(( elapsed > $SIMPL_CMD_MAX_EXEC_TIME )) && {
		_prompt_simpl_human_time_to_var $elapsed "prompt_simpl_cmd_exec_time"
	}
}

_prompt_simpl_set_title() {
	setopt localoptions noshwordsplit

	(( ${+EMACS} || ${+INSIDE_EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# Show hostname if connected via ssh.
	local hostname=
	if [[ -n $prompt_simpl_state[username] ]]; then
		hostname="${(%):-(%m) }"
	fi

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

_prompt_simpl_preexec() {
	if [[ -n $prompt_simpl_git_fetch_pattern ]]; then
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_simpl_git_fetch_pattern)(\ .*)?$ ]]; then
			async_flush_jobs 'prompt_simpl'
		fi
	fi

	typeset -g prompt_simpl_cmd_timestamp=$EPOCHSECONDS

	_prompt_simpl_set_title 'ignore-escape' "$PWD:t: $2"

	# Disallow Python virtualenv from updating the prompt. Set it to 12 if
	# untouched by the user to indicate that Simpl modified it.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-12}
}

_prompt_simpl_preprompt_render() {
	setopt localoptions noshwordsplit

	unset prompt_simpl_async_render_requested

	local -a preprompt_parts
	local r=$prompt_simpl_reset

	# Suspended jobs.
	local -i suspended=${(M)#jobstates:#suspended:*}
	if (( suspended )); then
		preprompt_parts+=("${SIMPL_SUSPENDED_JOBS_COLOR}${SIMPL_SUSPENDED_JOBS_SYMBOL}${r}")
	fi

	# Username and machine, if applicable (left side only when RPROMPT is off).
	if [[ -n $prompt_simpl_state[username] ]] && (( ! $SIMPL_ENABLE_RPROMPT )); then
		local in="${SIMPL_PREPOSITION_COLOR}in${r}"
		preprompt_parts+=("${prompt_simpl_state[username]} ${in}")
	fi

	# Path.
	preprompt_parts+=("${SIMPL_DIR_COLOR}%~${r}")

	# Git info.
	typeset -gA prompt_simpl_vcs_info
	if [[ -n $prompt_simpl_vcs_info[branch] ]]; then
		local branch_color="${SIMPL_GIT_BRANCH_COLOR}"
		[[ -n ${prompt_simpl_git_last_dirty_check_timestamp+x} ]] && branch_color="${SIMPL_GIT_BRANCH_CACHED_COLOR}"

		preprompt_parts+=("${SIMPL_PREPOSITION_COLOR}on${r}")
		if [[ -n $prompt_simpl_git_arrows ]]; then
			preprompt_parts+=("${SIMPL_GIT_ARROW_COLOR}${prompt_simpl_git_arrows}${r}")
		fi
		preprompt_parts+=("${branch_color}${prompt_simpl_vcs_info[branch]}${r}${prompt_simpl_git_dirty}")

		# Git action (rebase, merge, cherry-pick, etc).
		if [[ -n $prompt_simpl_vcs_info[action] ]]; then
			preprompt_parts+=("${SIMPL_GIT_ACTION_COLOR}${prompt_simpl_vcs_info[action]}${r}")
		fi

		# Git stash indicator.
		if [[ -n $prompt_simpl_git_stash ]]; then
			preprompt_parts+=("${SIMPL_GIT_STASH_COLOR}${SIMPL_GIT_STASH_SYMBOL}${r}")
		fi
	fi

	# Background jobs count.
	if [[ -n $(jobs) ]]; then
		preprompt_parts+=("${SIMPL_JOBS_COLOR}${SIMPL_JOBS_SYMBOL}%(1j.%j.)${r}")
	fi

	# Execution time.
	if [[ -n $prompt_simpl_cmd_exec_time ]]; then
		preprompt_parts+=("${SIMPL_EXEC_TIME_COLOR}${prompt_simpl_cmd_exec_time}${r}")
	fi

	local cleaned_ps1=$PROMPT
	local -H MATCH MBEGIN MEND
	if [[ $PROMPT = *$prompt_newline* ]]; then
		cleaned_ps1=${PROMPT##*${prompt_newline}}
	fi
	unset MATCH MBEGIN MEND

	local -ah ps1
	ps1=(
		${(j. .)preprompt_parts}
		$prompt_newline
		$cleaned_ps1
	)

	PROMPT="${(j..)ps1}"

	local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}"

	if [[ $1 == precmd ]]; then
		# Print a newline before the prompt, unless it's the first prompt.
		if [[ $SIMPL_NEWLINE_BEFORE_PROMPT == true ]]; then
			print
		fi
	elif [[ $prompt_simpl_last_prompt != $expanded_prompt ]]; then
		_prompt_simpl_reset_prompt
	fi

	SIMPL_NEWLINE_BEFORE_PROMPT=true

	typeset -g prompt_simpl_last_prompt=$expanded_prompt
}

_prompt_simpl_precmd() {
	setopt localoptions noshwordsplit

	_prompt_simpl_check_cmd_exec_time
	unset prompt_simpl_cmd_timestamp

	_prompt_simpl_set_title 'expand-prompt' '%~'

	_prompt_simpl_async_tasks

	# Virtual environment display via psvar[12].
	psvar[12]=
	if [[ -n $CONDA_DEFAULT_ENV ]]; then
		psvar[12]="${CONDA_DEFAULT_ENV//[$'\t\r\n']}"
	fi
	if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 12 ]]; then
		if [[ -n $VIRTUAL_ENV_PROMPT ]]; then
			psvar[12]="${VIRTUAL_ENV_PROMPT}"
		else
			psvar[12]="${VIRTUAL_ENV:t}"
		fi
		export VIRTUAL_ENV_DISABLE_PROMPT=12
	fi
	# Nix shell support.
	if [[ -n $IN_NIX_SHELL ]]; then
		psvar[12]="${name:-nix-shell}"
	fi

	# Reset VIM prompt symbol.
	_prompt_simpl_reset_prompt_symbol

	_prompt_simpl_preprompt_render "precmd"

	if [[ -n $ZSH_THEME ]]; then
		print "WARNING: Oh My Zsh themes are enabled (ZSH_THEME='${ZSH_THEME}'). Simpl might not be working correctly."
		print "For more information, see: https://github.com/eduarbo/simpl#oh-my-zsh"
		unset ZSH_THEME
	fi
}

_prompt_simpl_async_git_aliases() {
	setopt localoptions noshwordsplit
	local -a gitalias pullalias

	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})
		aliasname=${parts[1]#alias.}
		shift parts

		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}
}

_prompt_simpl_async_vcs_info() {
	setopt localoptions noshwordsplit

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	zstyle ':vcs_info:*' max-exports 3
	zstyle ':vcs_info:git*' formats '%b' '%R' '%a'
	zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[branch]=${vcs_info_msg_0_//\%/%%}
	info[top]=$vcs_info_msg_1_
	info[action]=$vcs_info_msg_2_

	print -r - ${(@kvq)info}
}

_prompt_simpl_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1
	local untracked_git_mode=$(command git config --get status.showUntrackedFiles)
	if [[ "$untracked_git_mode" != 'no' ]]; then
		untracked_git_mode='normal'
	fi

	export GIT_OPTIONAL_LOCKS=0

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain -u${untracked_git_mode})"
	fi

	return $?
}

_prompt_simpl_async_git_fetch() {
	setopt localoptions noshwordsplit

	local only_upstream=${1:-0}

	export GIT_TERMINAL_PROMPT=0
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

	# Prevent gpg-agent from corrupting the parent TTY.
	export GPG_TTY=

	local -a remote
	if ((only_upstream)); then
		local ref
		ref=$(command git symbolic-ref -q HEAD)
		remote=($(command git for-each-ref --format='%(upstream:remotename) %(refname)' $ref))
		if [[ -z $remote[1] ]]; then
			return 97
		fi
	fi

	local fail_code=99

	setopt localtraps monitor

	trap - HUP

	trap '
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			fail_code=98
			kill %%
		fi
	' CHLD

	command git -c gc.auto=0 fetch \
		--quiet \
		--no-tags \
		--no-prune-tags \
		--recurse-submodules=no \
		$remote &>/dev/null &
	wait $! || return $fail_code

	unsetopt monitor

	_prompt_simpl_async_git_arrows
}

_prompt_simpl_async_git_arrows() {
	setopt localoptions noshwordsplit
	command git rev-list --left-right --count HEAD...@'{u}'
}

_prompt_simpl_async_git_stash() {
	git rev-list --walk-reflogs --count refs/stash
}

_prompt_simpl_async_renice() {
	setopt localoptions noshwordsplit

	if command -v renice >/dev/null; then
		command renice +15 -p $$
	fi

	if command -v ionice >/dev/null; then
		command ionice -c 3 -p $$
	fi
}

_prompt_simpl_async_init() {
	typeset -g prompt_simpl_async_inited
	if ((${prompt_simpl_async_inited:-0})); then
		return
	fi
	prompt_simpl_async_inited=1
	async_start_worker "prompt_simpl" -u -n
	async_register_callback "prompt_simpl" _prompt_simpl_async_callback
	async_worker_eval "prompt_simpl" _prompt_simpl_async_renice
}

_prompt_simpl_async_tasks() {
	setopt localoptions noshwordsplit

	_prompt_simpl_async_init

	async_worker_eval "prompt_simpl" builtin cd -q $PWD

	typeset -gA prompt_simpl_vcs_info

	local -H MATCH MBEGIN MEND
	if [[ $PWD != ${prompt_simpl_vcs_info[pwd]}* ]]; then
		async_flush_jobs "prompt_simpl"

		unset prompt_simpl_git_dirty
		unset prompt_simpl_git_last_dirty_check_timestamp
		unset prompt_simpl_git_arrows
		unset prompt_simpl_git_stash
		unset prompt_simpl_git_fetch_pattern
		prompt_simpl_vcs_info[branch]=
		prompt_simpl_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_simpl" _prompt_simpl_async_vcs_info

	[[ -n $prompt_simpl_vcs_info[top] ]] || return

	_prompt_simpl_async_refresh
}

_prompt_simpl_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_simpl_git_fetch_pattern ]]; then
		typeset -g prompt_simpl_git_fetch_pattern="pull|fetch"
		async_job "prompt_simpl" _prompt_simpl_async_git_aliases
	fi

	async_job "prompt_simpl" _prompt_simpl_async_git_arrows

	if (( ${SIMPL_GIT_PULL} )) && [[ $prompt_simpl_vcs_info[top] != $HOME ]]; then
		zstyle -t :prompt:simpl:git:fetch only_upstream
		local only_upstream=$((? == 0))
		async_job "prompt_simpl" _prompt_simpl_async_git_fetch $only_upstream
	fi

	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_simpl_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${SIMPL_GIT_DELAY_DIRTY_CHECK} )); then
		unset prompt_simpl_git_last_dirty_check_timestamp
		async_job "prompt_simpl" _prompt_simpl_async_git_dirty ${SIMPL_GIT_UNTRACKED_DIRTY}
	fi

	# Git stash indicator (opt-in via zstyle).
	if zstyle -t ":prompt:simpl:git:stash" show; then
		async_job "prompt_simpl" _prompt_simpl_async_git_stash
	else
		unset prompt_simpl_git_stash
	fi
}

_prompt_simpl_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${SIMPL_GIT_DOWN_ARROW}
	(( left > 0 )) && arrows+=${SIMPL_GIT_UP_ARROW}

	[[ -n $arrows ]] || return
	typeset -g REPLY=$arrows
}

_prompt_simpl_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		\[async])
			if (( code == 2 )) || (( code == 3 )) || (( code == 130 )); then
				typeset -g prompt_simpl_async_inited=0
				async_stop_worker prompt_simpl
				_prompt_simpl_async_init
				_prompt_simpl_async_tasks

				unset prompt_simpl_async_render_requested
			fi
			;;
		\[async/eval])
			if (( code )); then
				_prompt_simpl_async_tasks
			fi
			;;
		_prompt_simpl_async_vcs_info)
			local -A info
			typeset -gA prompt_simpl_vcs_info

			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				return
			fi
			if [[ $info[top] = $prompt_simpl_vcs_info[top] ]]; then
				if [[ $prompt_simpl_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_simpl_vcs_info[pwd]=$PWD
				fi
			else
				prompt_simpl_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			[[ -n $info[top] ]] && [[ -z $prompt_simpl_vcs_info[top] ]] && _prompt_simpl_async_refresh

			prompt_simpl_vcs_info[branch]=$info[branch]
			prompt_simpl_vcs_info[top]=$info[top]
			prompt_simpl_vcs_info[action]=$info[action]

			do_render=1
			;;
		_prompt_simpl_async_git_aliases)
			if [[ -n $output ]]; then
				prompt_simpl_git_fetch_pattern+="|$output"
			fi
			;;
		_prompt_simpl_async_git_dirty)
			local prev_dirty=$prompt_simpl_git_dirty
			if (( code == 0 )); then
				unset prompt_simpl_git_dirty
			else
				typeset -g prompt_simpl_git_dirty="${SIMPL_GIT_DIRTY_COLOR}${SIMPL_GIT_DIRTY_SYMBOL}${prompt_simpl_reset}"
			fi

			[[ $prev_dirty != $prompt_simpl_git_dirty ]] && do_render=1

			(( $exec_time > 5 )) && prompt_simpl_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		_prompt_simpl_async_git_fetch|_prompt_simpl_async_git_arrows)
			case $code in
				0)
					local REPLY
					_prompt_simpl_check_git_arrows ${(ps:\t:)output}
					if [[ $prompt_simpl_git_arrows != $REPLY ]]; then
						typeset -g prompt_simpl_git_arrows=$REPLY
						do_render=1
					fi
					;;
				97)
					if [[ -n $prompt_simpl_git_arrows ]]; then
						typeset -g prompt_simpl_git_arrows=
						do_render=1
					fi
					;;
				99|98)
					# Git fetch failed.
					;;
				*)
					if [[ -n $prompt_simpl_git_arrows ]]; then
						unset prompt_simpl_git_arrows
						do_render=1
					fi
					;;
			esac
			;;
		_prompt_simpl_async_git_stash)
			local prev_stash=$prompt_simpl_git_stash
			typeset -g prompt_simpl_git_stash=$output
			[[ $prev_stash != $prompt_simpl_git_stash ]] && do_render=1
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_simpl_async_render_requested=1
		return
	fi

	[[ ${prompt_simpl_async_render_requested:-$do_render} = 1 ]] && _prompt_simpl_preprompt_render
	unset prompt_simpl_async_render_requested
}

_prompt_simpl_reset_prompt() {
	if [[ $CONTEXT == cont ]]; then
		# PS2 is active; resetting would lose the execution context (%_).
		return
	fi

	zle && zle .reset-prompt
}

_prompt_simpl_reset_prompt_symbol() {
	prompt_simpl_state[prompt]=${SIMPL_PROMPT_SYMBOL}
}

_prompt_simpl_update_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_simpl_state[prompt]=${${KEYMAP/vicmd/${SIMPL_PROMPT_VICMD_SYMBOL}}/(main|viins)/${SIMPL_PROMPT_SYMBOL}}

	_prompt_simpl_reset_prompt
}

_prompt_simpl_reset_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	_prompt_simpl_reset_prompt_symbol
}

_prompt_simpl_set_cursor_style() {
	# DECSCUSR (cursor shape) is widely supported by modern terminals.
	# Instead of an allowlist, bail out only on terminals known to not support it.
	case $TERM in
		dumb|linux|cons*) return;;
	esac

	case $KEYMAP in
		vicmd)      echo -ne "\e[1 q";;  # blinking block
		viins|main) echo -ne "\e[3 q";;  # blinking underline
	esac
}

_prompt_simpl_is_inside_container() {
	local -r nspawn_file='/run/host/container-manager'
	local -r podman_crio_file='/run/.containerenv'
	local -r docker_file='/.dockerenv'
	local -r k8s_token_file='/var/run/secrets/kubernetes.io/serviceaccount/token'
	local -r cgroup_file='/proc/1/cgroup'
	[[ "$container" == "lxc" ]] \
		|| [[ "$container" == "oci" ]] \
		|| [[ "$container" == "podman" ]] \
		|| [[ -r "$nspawn_file" ]] \
		|| [[ -r "$podman_crio_file" ]] \
		|| [[ -r "$docker_file" ]] \
		|| [[ -r "$k8s_token_file" ]] \
		|| [[ -r "$cgroup_file" && "$(< $cgroup_file)" = *(lxc|docker|containerd)* ]]
}

_prompt_simpl_state_setup() {
	setopt localoptions noshwordsplit

	local ssh_connection=${SSH_CONNECTION:-$PROMPT_SIMPL_SSH_CONNECTION}
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		local who_out
		who_out=$(who -m 2>/dev/null)
		if (( $? )); then
			local -a who_in
			who_in=( ${(f)"$(who 2>/dev/null)"} )
			who_out="${(M)who_in:#*[[:space:]]${TTY#/dev/}[[:space:]]*}"
		fi

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'
		local reHostname='([.][^. ]+){2}'

		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH

			export PROMPT_SIMPL_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	local r=$prompt_simpl_reset
	local prompt="%(#.${SIMPL_PROMPT_ROOT_SYMBOL}.${SIMPL_PROMPT_SYMBOL})"
	local user="%(#.${SIMPL_USER_ROOT_COLOR}%n.${SIMPL_USER_COLOR}%n)${r}"
	local username
	local show_user=0

	# Show user@host if logged in through SSH.
	[[ -n $ssh_connection ]] && show_user=1

	# Show user@host if inside a container (but not in GitHub Codespaces).
	[[ -z "${CODESPACES}" ]] && _prompt_simpl_is_inside_container && show_user=1

	# Show user@host if root.
	[[ $UID -eq 0 ]] && show_user=1

	# User setting overrides.
	(( ${SIMPL_ALWAYS_SHOW_USER} )) && show_user=1
	(( ${SIMPL_ALWAYS_SHOW_USER_AND_HOST} )) && show_user=1

	if (( show_user )); then
		username="${user}"
	fi

	if (( show_user )) && { (( ${SIMPL_ALWAYS_SHOW_USER_AND_HOST} )) || [[ -n $ssh_connection ]] || _prompt_simpl_is_inside_container; }; then
		local host_symbol="$SIMPL_HOST_SYMBOL_MAP[$( hostname -s )]"
		local host

		if [[ -n $host_symbol ]]; then
			host="${SIMPL_HOST_SYMBOL_COLOR}${host_symbol}${r}"
			username="${host} ${user}"
		else
			local at="${SIMPL_PREPOSITION_COLOR}at${r}"
			host="${SIMPL_HOST_COLOR}%m${r}"
			username="${user} ${at} ${host}"
		fi
	fi

	typeset -gA prompt_simpl_state
	prompt_simpl_state=(
		version  "3.0.0"
		username "${username}"
		prompt   "${prompt}"
	)
}

_prompt_simpl_setup() {
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	setopt transientrprompt

	if [[ -z $prompt_newline ]]; then
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	add-zsh-hook precmd _prompt_simpl_precmd
	add-zsh-hook preexec _prompt_simpl_preexec

	_prompt_simpl_state_setup

	zle -N _prompt_simpl_reset_prompt
	zle -N _prompt_simpl_update_vim_prompt_widget
	zle -N _prompt_simpl_reset_vim_prompt_widget
	zle -N _prompt_simpl_set_cursor_style
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish _prompt_simpl_reset_vim_prompt_widget
		add-zle-hook-widget zle-line-finish _prompt_simpl_set_cursor_style
		add-zle-hook-widget zle-keymap-select _prompt_simpl_update_vim_prompt_widget
		add-zle-hook-widget zle-keymap-select _prompt_simpl_set_cursor_style
		add-zle-hook-widget zle-line-init _prompt_simpl_set_cursor_style
	fi

	local r=$prompt_simpl_reset

	PROMPT="%(12V.${SIMPL_VENV_COLOR}%12v ${r}.)"
	PROMPT+="%(?.${SIMPL_PROMPT_SYMBOL_COLOR}.${SIMPL_PROMPT_SYMBOL_ERROR_COLOR})\${prompt_simpl_state[prompt]}${r} "

	PROMPT2="${SIMPL_PROMPT2_SYMBOL_COLOR}\${prompt_simpl_state[prompt]}${r} "

	if (( $SIMPL_ENABLE_RPROMPT )) && [[ -n $prompt_simpl_state[username] ]]; then
		RPROMPT="${prompt_simpl_state[username]}"
	fi

	typeset -ga prompt_simpl_debug_depth
	prompt_simpl_debug_depth=('%e' '%N' '%x')

	local -A ps4_parts
	ps4_parts=(
		depth     '%F{yellow}${(l:${(%)prompt_simpl_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_simpl_debug_depth[2]}:#${(%)prompt_simpl_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_simpl_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt    '%F{242}>%f '
	)
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	unset ZSH_THEME

	# Prevent conda from changing PS1 (we handle it ourselves).
	export CONDA_CHANGEPS1=no
}

_prompt_simpl_setup "$@"
