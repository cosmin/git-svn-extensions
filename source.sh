function git-current-branch {
    echo "`git branch | grep '*' | sed 's/* //'`"
}

function git-svn-transplant-to {
    current_branch=`git-current-branch`
    git checkout $1 && git merge $current_branch && git svn dcommit && git checkout $current_branch
}

function git-svn-remove-branch {
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    branches=`git config --list | grep branches | sed 's/.*branches=//' | sed 's/*:.*//'`
    if [ "$2" == "-f" ]; then
        svn rm "$svnremote/$branches$1" -m "Removing branch $1"
    else
        echo "Would remove branch $svnremote/$branches$1"
    fi
}

function git-svn-create-branch {
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    branches=`git config --list | grep branches | sed 's/.*branches=//' | sed 's/*:.*//'`
    current=`git svn info | grep "URL: " | cut -d ' ' -f 2`
    destination=$svnremote/$branches$1
    if [ "$2" == "-n" ]; then
        echo " ** Dry run only ** "
        echo "svn cp $current $destination -m \"creating branch\""
        echo "git svn fetch"
        echo "git branch --track svn-$1 $1"
        echo "git checkout svn-$1"
    else
        svn cp $current $destination -m "creating branch"
        git svn fetch
        git branch --track svn-$1 $1
        git checkout svn-$1
    fi
       
    echo "Created branch $1 at $destination (locally svn-$1)"
}

function git-svn-branches {
    git branch -r | cut -d ' ' -f 3 | grep -v '^trunk$' | grep -v '/'
}

function git-svn-prune-branches {
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    branches=`git config --list | grep branches | sed 's/.*branches=//' | sed 's/*:.*//'`
    remote_branches=" `svn ls $svnremote/$branches | sed 's/\/$//'` "
    local_branches=`git-svn-branches`

    for branch in $local_branches; do
        found=0
        for rbranch in $remote_branches; do
            if [[ $branch == $rbranch ]]; then
                  found=1
            fi
        done
        if [[ $found == 0 ]]; then
            if [[ "$1" == "-f" ]]; then
                git branch -r -D $branch
            else
                echo "Would remove $branch"
            fi
        fi
    done
}
