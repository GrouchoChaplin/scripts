
#
# Do you wish to update your shell profile to automatically initialize conda?
# This will activate conda on startup and change the command prompt when activated.
# If you'd prefer that conda's base environment not be activated on startup,
#    run the following command when conda is activated:
#
# conda config --set auto_activate_base false
#
# You can undo this by running `conda init --reverse $SHELL`? [yes|no]
#

export ANACONDA3_HOME="${HOME}/projects/3rdParty/anaconda3"

# export ${ANACONDA3_HOME}/anaconda3/:${ANACONDA3_HOME}/bin:${ANACONDA3_HOME}/condabin/:$PATH

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('${ANACONDA3_HOME}/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "${ANACONDA3_HOME}/etc/profile.d/conda.sh" ]; then
        . "${ANACONDA3_HOME}/etc/profile.d/conda.sh"
    else
        export PATH="${ANACONDA3_HOME}/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<


