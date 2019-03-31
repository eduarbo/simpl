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
# %B => Start boldface mode.
# %b => Stop boldface mode.
# %U => Start underline mode.
# %u => Stop underline mode.
# %S => Start standout mode.
# %s => Stop standout mode.
# %K => Start using a different bacKground colour. The syntax is identical to
#       that for %F and %f.
# %k => Stop using a different bacKground colour.
# %F => Start using a different foreground colour, if supported by the terminal.
#       The colour may be specified two ways: either as a numeric argument, as
#       normal, or by a sequence in braces following the %F, for example
#       %F{red}. In the latter case the values allowed are as described for the
#       fg zle_highlight attribute; Character Highlighting. This means that
#       numeric colours are allowed in the second format also.
# %f => Reset foreground color.
# %~ => current path
# %* => time
# %n => username
# %m => shortname host

# Conditional Substrings in Prompts:
# %(x.true-text.false-text) => Specifies a ternary expression

#   The left parenthesis may be preceded or followed by a positive integer n,
#   which defaults to zero. A negative integer will be multiplied by -1. The
#   test character x may be any of the following:
#   ! => True if the shell is running with privileges
#   ? => True if the exit status of the last command was n
#   # => True if the effective uid of the current process is n

# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line

# Configuration
# Set options in the SIMPL namespace to not pollute the global namespace
typeset -gA SIMPL

: ${SIMPL[ALWAYS_SHOW_USER]:=0}
: ${SIMPL[ALWAYS_SHOW_USER_AND_HOST]:=0}
: ${SIMPL[CMD_MAX_EXEC_TIME]:=1}
: ${SIMPL[ENABLE_RPROMPT]:=0}
: ${SIMPL[GIT_DELAY_DIRTY_CHECK]:=1800}
: ${SIMPL[GIT_PULL]:=1}
: ${SIMPL[GIT_UNTRACKED_DIRTY]:=1}

# symbols
: ${SIMPL[GIT_DIRTY_SYMBOL]:="•"}
: ${SIMPL[GIT_DOWN_ARROW]:="⇣"}
: ${SIMPL[GIT_UP_ARROW]:="⇡"}
: ${SIMPL[JOBS_SYMBOL]:="↻"}
: ${SIMPL[PROMPT_ROOT_SYMBOL]:="#"}
: ${SIMPL[PROMPT_SYMBOL]:="❱"}

# colors
: ${SIMPL[DIR_COLOR]:="%F{magenta}"}
: ${SIMPL[EXEC_TIME_COLOR]:="%B%F{8}"}
: ${SIMPL[GIT_ARROW_COLOR]:="%B%F{9}"}
: ${SIMPL[GIT_BRANCH_COLOR]:="%F{14}"}
: ${SIMPL[GIT_DIRTY_COLOR]:="%F{9}"}
: ${SIMPL[HOST_COLOR]:="%F{10}"}
: ${SIMPL[HOST_SYMBOL_COLOR]:="%B%F{10}"}
: ${SIMPL[JOBS_COLOR]:="%B%F{8}"}
: ${SIMPL[PREPOSITION_COLOR]:="%F{8}"}
: ${SIMPL[PROMPT_SYMBOL_COLOR]:="%F{11}"}
: ${SIMPL[PROMPT_SYMBOL_ERROR_COLOR]:="%F{red}"}
: ${SIMPL[PROMPT2_SYMBOL_COLOR]:="%F{8}"}
: ${SIMPL[USER_COLOR]:="%F{10}"}
: ${SIMPL[USER_ROOT_COLOR]:="%B%F{red}"}
: ${SIMPL[VENV_COLOR]:="%F{yellow}"}

# Utils
cl="%f%s%u%k%b"

# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
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

	# store human readable time in variable as specified by caller
	typeset -g "${var}"="${human}"
}

# stores (into prompt_simpl_cmd_exec_time) the exec time of the last command if set threshold was exceeded
_prompt_simpl_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_simpl_cmd_timestamp:-$EPOCHSECONDS} ))
	typeset -g prompt_simpl_cmd_exec_time=
	(( elapsed > ${SIMPL[CMD_MAX_EXEC_TIME]} )) && {
		_prompt_simpl_human_time_to_var $elapsed "prompt_simpl_cmd_exec_time"
	}
}

_prompt_simpl_set_title() {
	setopt localoptions noshwordsplit

	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# Show hostname if connected via ssh.
	local hostname=
	if [[ -n $prompt_simpl_state[username] ]]; then
		# Expand in-place in case ignore-escape is used.
		hostname="${(%):-(%m) }"
	fi

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	# Set title atomically in one print statement so that it works
	# when XTRACE is enabled.
	print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

_prompt_simpl_preexec() {
	if [[ -n $prompt_simpl_git_fetch_pattern ]]; then
		# detect when git is performing pull/fetch (including git aliases).
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_simpl_git_fetch_pattern)(\ .*)?$ ]]; then
			# we must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_simpl'
		fi
	fi

	typeset -g prompt_simpl_cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title while a process is active
	_prompt_simpl_set_title 'ignore-escape' "$PWD:t: $2"

	# Disallow python virtualenv from updating the prompt, set it to 12 if
	# untouched by the user to indicate that Simpl modified it. Here we use
	# magic number 12, same as in psvar.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-12}
}

_prompt_simpl_preprompt_render() {
	setopt localoptions noshwordsplit

	# Initialize the preprompt array.
	local -a preprompt_parts

	# Username and machine, if applicable.
	if [[ -n $prompt_simpl_state[username] ]] && (( ! $SIMPL[ENABLE_RPROMPT] )); then
		local in="${SIMPL[PREPOSITION_COLOR]}in${cl}"
		preprompt_parts+=("${prompt_simpl_state[username]} ${in}")
	fi

	# Set the path.
	preprompt_parts+=("${SIMPL[DIR_COLOR]}%~${cl}")

	# Add git branch and dirty status info.
	typeset -gA prompt_simpl_vcs_info

	# Git pull/push arrows.
	if [[ -n $prompt_simpl_vcs_info[branch] ]]; then
		# Set color for git branch/dirty status, change color if dirty checking has
		# been delayed.
		local branch_color="${SIMPL[GIT_BRANCH_COLOR]}"
		[[ -n ${prompt_simpl_git_last_dirty_check_timestamp+x} ]] && branch_color="${cl}%F{red}"

		preprompt_parts+=("${SIMPL[PREPOSITION_COLOR]}on${cl}")
		if [[ -n $prompt_simpl_git_arrows ]]; then
			preprompt_parts+=("${SIMPL[GIT_ARROW_COLOR]}${prompt_simpl_git_arrows}${cl}")
		fi
		preprompt_parts+=("${branch_color}${prompt_simpl_vcs_info[branch]}${cl}${prompt_simpl_git_dirty}")
	fi

	# Number of jobs in background.
	if [[ -n $(jobs) ]]; then
		preprompt_parts+=("${SIMPL[JOBS_COLOR]}${SIMPL[JOBS_SYMBOL]}%(1j.%j.)${cl}")
	fi

	# Execution time.
	if [[ -n $prompt_simpl_cmd_exec_time ]]; then
		preprompt_parts+=("${SIMPL[EXEC_TIME_COLOR]}${prompt_simpl_cmd_exec_time}${cl}")
	fi

	local cleaned_ps1=$PROMPT
	local -H MATCH MBEGIN MEND
	if [[ $PROMPT = *$prompt_newline* ]]; then
		# Remove everything from the prompt until the newline. This
		# removes the preprompt and only the original PROMPT remains.
		cleaned_ps1=${PROMPT##*${prompt_newline}}
	fi
	unset MATCH MBEGIN MEND

	# Construct the new prompt with a clean preprompt.
	local -ah ps1
	ps1=(
		${(j. .)preprompt_parts}  # Join parts, space separated.
		$prompt_newline           # Separate preprompt and prompt.
		$cleaned_ps1
	)

	PROMPT="${(j..)ps1}"

	# Expand the prompt for future comparision.
	local expanded_prompt
	expanded_prompt="${(S%%)PROMPT}"

	if [[ $1 == precmd ]]; then
		# Initial newline, for spaciousness.
		print
	elif [[ $prompt_simpl_last_prompt != $expanded_prompt ]]; then
		# Redraw the prompt.
		zle && zle .reset-prompt
	fi

	typeset -g prompt_simpl_last_prompt=$expanded_prompt
}

_prompt_simpl_precmd() {
	# check exec time and store it in a variable
	_prompt_simpl_check_cmd_exec_time
	unset prompt_simpl_cmd_timestamp

	# shows the full path in the title
	_prompt_simpl_set_title 'expand-prompt' '%~'

	# preform async git dirty check and fetch
	_prompt_simpl_async_tasks

	# Check if we should display the virtual env, we use a sufficiently high
	# index of psvar (12) here to avoid collisions with user defined entries.
	psvar[12]=
	# Check if a conda environment is active and display it's name
	if [[ -n $CONDA_DEFAULT_ENV ]]; then
		psvar[12]="${CONDA_DEFAULT_ENV//[$'\t\r\n']}"
	fi
	# When VIRTUAL_ENV_DISABLE_PROMPT is empty, it was unset by the user and
	# Simpl should take back control.
	if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 12 ]]; then
		psvar[12]="${VIRTUAL_ENV:t}"
		export VIRTUAL_ENV_DISABLE_PROMPT=12
	fi

	# print the preprompt
	_prompt_simpl_preprompt_render "precmd"

	if [[ -n $ZSH_THEME ]]; then
		print "WARNING: Oh My Zsh themes are enabled (ZSH_THEME='${ZSH_THEME}'). Simpl might not be working correctly."
		print "For more information, see: https://github.com/eduarbo/simpl#oh-my-zsh"
		unset ZSH_THEME  # Only show this warning once.
	fi
}

_prompt_simpl_async_git_aliases() {
	setopt localoptions noshwordsplit
	local -a gitalias pullalias

	# list all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # split line on spaces
		aliasname=${parts[1]#alias.}  # grab the name (alias.[name])
		shift parts                   # remove aliasname

		# check alias for pull or fetch (must be exact match).
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # join on pipe (for use in regex).
}

_prompt_simpl_async_vcs_info() {
	setopt localoptions noshwordsplit

	# configure vcs_info inside async task, this frees up vcs_info
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
	# export branch (%b) and git toplevel (%R)
	zstyle ':vcs_info:git*' formats '%b' '%R'
	zstyle ':vcs_info:git*' actionformats '%b|%a' '%R'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[top]=$vcs_info_msg_1_
	info[branch]=$vcs_info_msg_0_

	print -r - ${(@kvq)info}
}

# fastest possible way to check if repo is dirty
_prompt_simpl_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	return $?
}

_prompt_simpl_async_git_fetch() {
	setopt localoptions noshwordsplit

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	export GIT_TERMINAL_PROMPT=0
	# set ssh BachMode to disable all interactive ssh password prompting
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

	# Default return code, indicates Git fetch failure.
	local fail_code=99

	# Guard against all forms of password prompts. By setting the shell into
	# MONITOR mode we can notice when a child process prompts for user input
	# because it will be suspended. Since we are inside an async worker, we
	# have no way of transmitting the password and the only option is to
	# kill it. If we don't do it this way, the process will corrupt with the
	# async worker.
	setopt localtraps monitor

	# Make sure local HUP trap is unset to allow for signal propagation when
	# the async worker is flushed.
	trap - HUP

	trap '
		# Unset trap to prevent infinite loop
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			# Set fail code to password prompt and kill the fetch.
			fail_code=98
			kill %%
		fi
	' CHLD

	command git -c gc.auto=0 fetch >/dev/null &
	wait $! || return $fail_code

	unsetopt monitor

	# check arrow status after a successful git fetch
	_prompt_simpl_async_git_arrows
}

_prompt_simpl_async_git_arrows() {
	setopt localoptions noshwordsplit
	command git rev-list --left-right --count HEAD...@'{u}'
}

_prompt_simpl_async_tasks() {
	setopt localoptions noshwordsplit

	# initialize async worker
	((!${prompt_simpl_async_init:-0})) && {
		async_start_worker "prompt_simpl" -u -n
		async_register_callback "prompt_simpl" _prompt_simpl_async_callback
		typeset -g prompt_simpl_async_init=1
	}

	# Update the current working directory of the async worker.
	async_worker_eval "prompt_simpl" builtin cd -q $PWD

	typeset -gA prompt_simpl_vcs_info

	local -H MATCH MBEGIN MEND
	if [[ $PWD != ${prompt_simpl_vcs_info[pwd]}* ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_simpl"

		# reset git preprompt variables, switching working tree
		unset prompt_simpl_git_dirty
		unset prompt_simpl_git_last_dirty_check_timestamp
		unset prompt_simpl_git_arrows
		unset prompt_simpl_git_fetch_pattern
		prompt_simpl_vcs_info[branch]=
		prompt_simpl_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_simpl" _prompt_simpl_async_vcs_info

	# # only perform tasks inside git working tree
	[[ -n $prompt_simpl_vcs_info[top] ]] || return

	_prompt_simpl_async_refresh
}

_prompt_simpl_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_simpl_git_fetch_pattern ]]; then
		# we set the pattern here to avoid redoing the pattern check until the
		# working three has changed. pull and fetch are always valid patterns.
		typeset -g prompt_simpl_git_fetch_pattern="pull|fetch"
		async_job "prompt_simpl" _prompt_simpl_async_git_aliases
	fi

	async_job "prompt_simpl" _prompt_simpl_async_git_arrows

	# do not preform git fetch if it is disabled or in home folder.
	if (( ${SIMPL[GIT_PULL]} )) && [[ $prompt_simpl_vcs_info[top] != $HOME ]]; then
		# tell worker to do a git fetch
		async_job "prompt_simpl" _prompt_simpl_async_git_fetch
	fi

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_simpl_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${SIMPL[GIT_DELAY_DIRTY_CHECK]} )); then
		unset prompt_simpl_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_simpl" _prompt_simpl_async_git_dirty ${SIMPL[GIT_UNTRACKED_DIRTY]}
	fi
}

_prompt_simpl_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${SIMPL[GIT_DOWN_ARROW]}
	(( left > 0 )) && arrows+=${SIMPL[GIT_UP_ARROW]}

	[[ -n $arrows ]] || return
	typeset -g REPLY=$arrows
}

_prompt_simpl_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	case $job in
		_prompt_simpl_async_vcs_info)
			local -A info
			typeset -gA prompt_simpl_vcs_info

			# parse output (z) and unquote as array (Q@)
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				# The path has changed since the check started, abort.
				return
			fi
			# check if git toplevel has changed
			if [[ $info[top] = $prompt_simpl_vcs_info[top] ]]; then
				# if stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be toplevel, so we update pwd
				if [[ $prompt_simpl_vcs_info[pwd] =~ ^$PWD ]]; then
					prompt_simpl_vcs_info[pwd]=$PWD
				fi
			else
				# store $PWD to detect if we (maybe) left the git path
				prompt_simpl_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# update has a git toplevel set which means we just entered a new
			# git directory, run the async refresh tasks
			[[ -n $info[top] ]] && [[ -z $prompt_simpl_vcs_info[top] ]] && _prompt_simpl_async_refresh

			# always update branch and toplevel
			prompt_simpl_vcs_info[branch]=$info[branch]
			prompt_simpl_vcs_info[top]=$info[top]

			do_render=1
			;;
		_prompt_simpl_async_git_aliases)
			if [[ -n $output ]]; then
				# append custom git aliases to the predefined ones.
				prompt_simpl_git_fetch_pattern+="|$output"
			fi
			;;
		_prompt_simpl_async_git_dirty)
			local prev_dirty=$prompt_simpl_git_dirty
			if (( code == 0 )); then
				prompt_simpl_git_dirty=
			else
				prompt_simpl_git_dirty="${SIMPL[GIT_DIRTY_COLOR]}${SIMPL[GIT_DIRTY_SYMBOL]}${cl}"
			fi

			[[ $prev_dirty != $prompt_simpl_git_dirty ]] && do_render=1

			# When prompt_simpl_git_last_dirty_check_timestamp is set, the git info is displayed in a different color.
			# To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
			# variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_simpl_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		_prompt_simpl_async_git_fetch|_prompt_simpl_async_git_arrows)
			# _prompt_simpl_async_git_fetch executes _prompt_simpl_async_git_arrows
			# after a successful fetch.
			case $code in
				0)
					local REPLY
					_prompt_simpl_check_git_arrows ${(ps:\t:)output}
					if [[ $prompt_simpl_git_arrows != $REPLY ]]; then
						typeset -g prompt_simpl_git_arrows=$REPLY
						do_render=1
					fi
					;;
				99|98)
					# Git fetch failed.
					;;
				*)
					# Non-zero exit status from _prompt_simpl_async_git_arrows,
					# indicating that there is no upstream configured.
					if [[ -n $prompt_simpl_git_arrows ]]; then
						unset prompt_simpl_git_arrows
						do_render=1
					fi
					;;
			esac
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_simpl_async_render_requested=1
		return
	fi

	[[ ${prompt_simpl_async_render_requested:-$do_render} = 1 ]] && _prompt_simpl_preprompt_render
	unset prompt_simpl_async_render_requested
}

_prompt_simpl_set_cursor_style() {
	local my_terms=(xterm-256color xterm-kitty)

	# Change cursor shape only on tested $TERMs
	if [[ ${my_terms[(ie)$TERM]} -le ${#my_terms} ]]; then
		# \e[0 q or \e[ q: reset to whatever's defined in the profile settings
		# \e[1 q: blinking block
		# \e[2 q: steady block
		# \e[3 q: blinking underline
		# \e[4 q: steady underline
		# \e[5 q: blinking I-beam
		# \e[6 q: steady I-beam
		case $KEYMAP in
			# vi emulation - command mode
			vicmd)      echo -ne "\e[1 q";;
			# vi emulation - insert mode
			viins|main) echo -ne "\e[3 q";;
		esac
	fi
}

_prompt_simpl_state_setup() {
	setopt localoptions noshwordsplit

	# Check SSH_CONNECTION and the current state.
	local ssh_connection=${SSH_CONNECTION:-$PROMPT_SIMPL_SSH_CONNECTION}
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		# When changing user on a remote system, the $SSH_CONNECTION
		# environment variable can be lost, attempt detection via who.
		local who_out
		who_out=$(who -m 2>/dev/null)
		if (( $? )); then
			# Who am I not supported, fallback to plain who.
			who_out=$(who 2>/dev/null | grep ${TTY#/dev/})
		fi

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'  # Simplified, only checks partial pattern.
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'   # Simplified, allows invalid ranges.
		# Here we assume two non-consecutive periods represents a
		# hostname. This matches foo.bar.baz, but not foo.bar.
		local reHostname='([.][^. ]+){2}'

		# Usually the remote address is surrounded by parenthesis, but
		# not on all systems (e.g. busybox).
		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH

			# Export variable to allow detection propagation inside
			# shells spawned by this one (e.g. tmux does not always
			# inherit the same tty, which breaks detection).
			export PROMPT_SIMPL_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	local user="%(#.${SIMPL[USER_ROOT_COLOR]}%n.${SIMPL[USER_COLOR]}%n)${cl}"
	local username

	if (( ${SIMPL[ALWAYS_SHOW_USER]} )) || [[ "$SSH_CONNECTION" != '' ]]; then
		username="${user}"
	fi

	# show hostname if connected via ssh or if overridden by option
	if (( ${SIMPL[ALWAYS_SHOW_USER_AND_HOST]} )) || [[ "$SSH_CONNECTION" != '' ]]; then
		local host_symbol="$PROMPT_SIMPL_HOSTNAME_SYMBOL_MAP[$( hostname -s )]"
		local host

		if [[ -n $host_symbol ]]; then
			host="${SIMPL[HOST_SYMBOL_COLOR]}${host_symbol}${cl}"
			username="${host} ${user}"
		else
			local at="${SIMPL[PREPOSITION_COLOR]}at${cl}"
			host="${SIMPL[HOST_COLOR]}%m${cl}"
			username="${user} ${at} ${host}"
		fi
	fi

	typeset -gA prompt_simpl_state
	prompt_simpl_state=(
		username "${username}"
		prompt	 "%(#.${SIMPL[PROMPT_ROOT_SYMBOL]}.${SIMPL[PROMPT_SYMBOL]})${cl}"
	)
}

_prompt_simpl_setup() {
	# Prevent percentage showing up if output doesn't end with a newline.
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# borrowed from promptinit, sets the prompt options in case simpl was not
	# initialized via promptinit.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	setopt transientrprompt # only have the rprompt on the last line

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	# The add-zle-hook-widget function is not guaranteed
	# to be available, it was added in Zsh 5.3.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	add-zsh-hook precmd _prompt_simpl_precmd
	add-zsh-hook preexec _prompt_simpl_preexec

	_prompt_simpl_state_setup

	zle -N _prompt_simpl_set_cursor_style
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish _prompt_simpl_set_cursor_style
		add-zle-hook-widget zle-keymap-select _prompt_simpl_set_cursor_style
		add-zle-hook-widget zle-line-init _prompt_simpl_set_cursor_style
	fi

	PROMPT="%(12V.${SIMPL[VENV_COLOR]}%12v ${cl}.)"
	# prompt turns red if the previous command didn't exit with 0
	PROMPT+="%(?.${SIMPL[PROMPT_SYMBOL_COLOR]}.${SIMPL[PROMPT_SYMBOL_ERROR_COLOR]})${prompt_simpl_state[prompt]}${cl} "

	PROMPT2="${SIMPL[PROMPT2_SYMBOL_COLOR]}${prompt_simpl_state[prompt]}${cl} "

	# right prompt
	if (( $SIMPL[ENABLE_RPROMPT] )) && [[ -n $prompt_simpl_state[username] ]]; then
		# display username and host
		RPROMPT="${prompt_simpl_state[username]}"
	fi

	# Store prompt expansion symbols for in-place expansion via (%). For
	# some reason it does not work without storing them in a variable first.
	typeset -ga prompt_simpl_debug_depth
	prompt_simmpl_debug_depth=('%e' '%N' '%x')

	# Compare is used to check if %N equals %x. When they differ, the main
	# prompt is used to allow displaying both file name and function. When
	# they match, we use the secondary prompt to avoid displaying duplicate
	# information.
	local -A ps4_parts
	ps4_parts=(
		depth 	  '%F{yellow}${(l:${(%)prompt_simpl_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_simpl_debug_depth[2]}:#${(%)prompt_simpl_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_simpl_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt 	  '%F{242}>%f '
	)
	# Combine the parts with conditional logic. First the `:+` operator is
	# used to replace `compare` either with `main` or an ampty string. Then
	# the `:-` operator is used so that if `compare` becomes an empty
	# string, it is replaced with `secondary`.
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	# Improve the debug prompt (PS4), show depth by repeating the +-sign and
	# add colors to highlight essential parts like file and function name.
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	unset ZSH_THEME  # Guard against Oh My Zsh themes overriding Simpl.
}

_prompt_simpl_setup "$@"
