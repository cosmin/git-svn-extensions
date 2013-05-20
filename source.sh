# Prints the name of the current local branch.
function git-current-branch {
    # "git branch" prints a list of local branches, the current one being marked with a "*". Extract it.
    echo "`git branch | grep '*' | sed 's/* //'`"
}

# Prints the name of the remote branch (subversion trunk, branch or tag) tracked by the current local branch.
function git-current-remote-branch {
    # This is the current remote URL corresponding to the local branch
    current_url=`git svn info --url`
    # Obtain the URL parts corresponding to the base repository address, and the prefixes for the trunk, the branches, and the tags
    base_url=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    trunk_url=$base_url/`git config --list | grep "svn-remote.svn.fetch" | cut -d '=' -f 2 | sed 's/:.*//'`
    branches_url=$base_url/`git config --list | grep branches | sed 's/.*branches=//' | sed 's/*:.*//'`
    tags_url=$base_url/`git config --list | grep tags | sed 's/.*tags=//' | sed 's/*:.*//'`
    # Check if the current URL matches the trunk URL
    if [ $trunk_url == $current_url ]; then
        if [ "$1" == "-s" ]; then
            echo "trunk"
        else
            echo "You are on trunk"
        fi
    # ...or has the branches URL as a prefix
    elif [ `echo $current_url | grep $branches_url` ]; then
        # Escape / in order to use the URL as a regular expression in sed
        escaped_prefix=`echo $branches_url | sed 's/\//\\\\\//g'`
        if [ "$1" == "-s" ]; then
            echo `echo $current_url | sed "s/$escaped_prefix//"`
        else
            echo You are on branch `echo $current_url | sed "s/$escaped_prefix//"`
        fi
    # ...or has the tags URL as a prefix
    elif [ `echo $current_url | grep $tags_url` ]; then
        # Escape / in order to use the URL as a regular expression in sed
        escaped_prefix=`echo $tags_url | sed 's/\//\\\\\//g'`
        if [ "$1" == "-s" ]; then
            echo `echo $current_url | sed "s/$escaped_prefix//"`
        else
            echo You are on tag `echo $current_url | sed "s/$escaped_prefix//"`
        fi
    else
        if [ "$1" == "-s" ]; then
            echo "unknown"
        else
            echo "You are on an unknown remote branch"
        fi
    fi
}

# Merge the changes from the current branch into another branch (either an existing local branch or a remote branch) and
# commit them to the remote server. After that, switch back to the original branch.
function git-svn-transplant-to {
    current_branch=`git-current-branch`
    git checkout $1 && git merge $current_branch && git svn dcommit && git checkout $current_branch
}

# Remove a remote branch from the central server. Equivalent of "svn remove <branch> && svn commit".
function git-svn-remove-branch {
    # Compute the location of the remote branches
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    branches=$svnremote/`git config --list | grep branches | sed 's/.*branches=//' | sed 's/*:.*//'`
    if [ "$2" == "-f" ]; then
        # Remove the branch using svn
        svn rm "$branches$1" -m "Removing branch $1"
    else
        echo "Would remove branch $branches$1"
        echo "To actually remove the branch, use:"
        echo "  ${FUNCNAME[0]} $1 -f"
    fi
}

# Remove a remote tag from the central server. Equivalent of "svn remove <tag> && svn commit".
# Note that removing tags is not recommended.
function git-svn-remove-tag {
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    tags=$svnremote/`git config --list | grep tags | sed 's/.*tags=//' | sed 's/*:.*//'`
    if [ "$2" == "-f" ]; then
        svn rm "$tags$1" -m "Removing tag $1"
    else
        echo "Would remove tag $tag$1"
        echo "To actually remove the tag, use:"
        echo "  ${FUNCNAME[0]} $1 -f"
    fi
}

# Create a remote svn branch from the currently tracked one, and check it out in a new local branch.
function git-svn-create-branch {
    # Compute the location of the remote branches
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    branches=$svnremote/`git config --list | grep branches | sed 's/.*branches=//' | sed 's/*:.*//'`
    destination=$branches$1
    # Determine the current remote branch (or trunk)
    current=`git svn info --url`
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

# Create a remote svn tag from the currently tracked branch/trunk.
function git-svn-create-tag {
    if [ "$2" == "-n" ]; then
        echo " ** Dry run only ** "
    fi
    # Determine the name of the current remote branch (or trunk)
    source=`git-current-remote-branch -s`
    # Determine if there are local changes that are not pushed to the central server
    if ((git svn dcommit -n > /dev/null 2> /dev/null) && [[ "`git svn dcommit -n 2> /dev/null | grep diff-tree | wc -l`" == "0" ]]); then
        echo "Using $source as the source branch to tag"
    else
        echo "Local branch contains changes, please push to the svn repository or checkout a clean branch."
        return 1
    fi
    # Compute the location of the remote tags
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    tags=$svnremote/`git config --list | grep tags | sed 's/.*tags=//' | sed 's/*:.*//'`
    destination=$tags$1
    # Determine the remote URL of the current branch
    current=`git svn info --url`
    if [ "$2" == "-n" ]; then
        echo "svn cp $current $destination -m \"creating tag $1 from $source\""
        echo "git svn fetch"
        echo "Would create tag $1 from $source at $destination"
    else
        # Create the tag remotely
        svn cp $current $destination -m "creating tag $1 from $source"
        # Update remote tag names
        git svn fetch
        echo "Created tag $1 from $source at $destination"
    fi
}

# List the remote branches, as known locally by git.
function git-svn-branches {
    # List all known remote branches and filter out the trunk (named trunk) and the tags (which contain a / in their name)
    git branch -r | cut -d ' ' -f 3 | grep -E -v '^trunk(@.*)?$' | grep -v '/'
}

# List the remote tags, as known locally by git.
function git-svn-tags {
    # List all known remote branches and filter only the tags, which contain a / in their name
    git branch -r | cut -d ' ' -f 3 | grep '/' | cut -d '/' -f2
}

# Remove from the git references fake trunk remotes pointing to different versions.
# These are created when the codebase was moved on SVN from one location to the other.
# Their names look like "trunk@35107"
function git-svn-prune-trunk {
    # List the versioned trunk remotes
    to_remove=`git branch -r | grep --color=never 'trunk@'`

    # Check each locally known remote branch
    for branch in $to_remove; do
        if [[ "$1" == "-f" ]]; then
            git branch -r -D $branch
        else
            echo "Would remove $branch"
        fi
    done

    # If this was only a dry run, indicate how to actually prune
    if [[ "$1" != "-f" && "$1" != "-q" ]]; then
        echo "To actually prune dead versions, use:"
        echo "  ${FUNCNAME[0]} -f"
    fi
}

# Remove branches which no longer exist remotely from the local git references.
function git-svn-prune-branches {
    # List the real remote and locally known remote branches
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    branches=$svnremote/`git config --list | grep branches | grep -v svn-remote.svn.fetch | sed 's/.*branches=//' | sed 's/*:.*//'`
    remote_branches=" `svn ls $branches | sed 's/\/$//'` "
    local_branches=`git-svn-branches`

    # Check each locally known remote branch
    for branch in $local_branches; do
        found=0
        # Search it in the list of real remote branches
        for rbranch in $remote_branches; do
            if [[ $branch == $rbranch ]]; then
                  found=1
            fi
        done
        # If not found, remove it
        if [[ $found == 0 ]]; then
            if [[ "$1" == "-f" ]]; then
                git branch -r -D $branch
            else
                echo "Would remove $branch"
            fi
        fi
    done

    # If this was only a dry run, indicate how to actually prune
    if [[ "$1" != "-f" && "$1" != "-q" ]]; then
        echo "To actually prune branches, use:"
        echo "  ${FUNCNAME[0]} -f"
    fi
}

# Remove tags which no longer exist remotely from the local git references.
function git-svn-prune-tags {
    # List the real remote and locally known remote tags
    svnremote=`git config --list | grep "svn-remote.svn.url" | cut -d '=' -f 2`
    tags=`git config --list | grep tags | sed 's/.*tags=//' | sed 's/*:.*//'`
    remote_tags=" `svn ls $svnremote/$tags | sed 's/\/$//'` "
    local_tags=`git-svn-tags`

    # Check each locally known remote tag
    for tag in $local_tags; do
        found=0
        # Search it in the list of real remote tags
        for rtag in $remote_tags; do
            if [[ $tag == $rtag ]]; then
                  found=1
            fi
        done
        # If not found, remove it
        if [[ $found == 0 ]]; then
            if [[ "$1" == "-f" ]]; then
                git branch -r -D tags/$tag
            else
                echo "Would remove tags/$tag"
            fi
        fi
    done

    # If this was only a dry run, indicate how to actually prune
    if [[ "$1" != "-f" && "$1" != "-q" ]]; then
        echo "To actually prune tags, use:"
        echo "  ${FUNCNAME[0]} -f"
    fi
}

function git-svn-prune-remotes {
    git-svn-prune-trunk ${1:--q}
    git-svn-prune-branches ${1:--q}
    git-svn-prune-tags ${1:--q}

    # If this was only a dry run, indicate how to actually prune
    if [[ "$1" != "-f" ]]; then
        echo "To actually prune dead remotes, use:"
        echo "  ${FUNCNAME[0]} -f"
    fi
}

function git-svn-up {
    git stash && git svn rebase && git stash pop
}

function git-svn-convert-tags {
  #!/bin/sh
  #
  # git-svn-convert-tags
  # Convert Subversion "tags" into Git tags
  for tag in `git branch -r | grep "  tags/" | sed 's/  tags\///'`; do
    GIT_COMMITTER_DATE="$(git log -1 --pretty=format:"%ad" tags/"$tag")" 
    GIT_COMMITTER_EMAIL="$(git log -1 --pretty=format:"%ce" tags/"$tag")"
    GIT_COMMITTER_NAME="$(git log -1 --pretty=format:"%cn" tags/"$tag")"
    GIT_MESSAGE="$(git log -1 --pretty=format:%s%n%b tags/"$tag")"
    git tag -m "$GIT_MESSAGE" $tag refs/remotes/tags/$tag
    git branch -rd "tags/""$tag"
  done
}

# Create a git branch for each remote SVN branch
function git-svn-convert-branches {
    for branch in `git-svn-branches`; do
        git branch "${branch}" "remotes/${branch}"
        git branch -rD "${branch}"
    done
}

# Remove tags that match the provided regular expression (Perl syntax).
# The first parameter is mandatory and must be a regular expression of tag names to remove.
# Only do a dry run, printing what would be removed, if the second parameter is missing or is not "-f"
function git-svn-filter-tags {
    svn_tags=`git-svn-tags`
    git_tags=`git tag`

    # Check each remote tag
    for tag in $svn_tags ; do
        found=`echo $tag | grep -P $1`
        # If it matches, remove it
        if [[ -n $found ]]; then
            if [[ "$2" == "-f" ]]; then
                git branch -D -r tags/$tag
            else
                echo "Would remove remote tags/$tag"
            fi
        fi
    done

    # Check each git tag
    for tag in $git_tags ; do
        found=`echo $tag | grep -P $1`
        # If it matches, remove it
        if [[ -n $found ]]; then
            if [[ "$2" == "-f" ]]; then
                git tag -d $tag
            else
                echo "Would remove tag $tag"
            fi
        fi
    done

    # If this was only a dry run, indicate how to actually prune
    if [[ "$2" != "-f" && "$2" != "-q" ]]; then
        echo "To actually remove tags, use:"
        echo "  ${FUNCNAME[0]} $1 -f"
    fi
}

# Remove branches that match the provided regular expression (Perl syntax).
# The first parameter is mandatory and must be a regular expression of branch names to remove.
# Only do a dry run, printing what would be removed, if the second parameter is missing or is not "-f"
function git-svn-filter-branches {
    svn_branches=`git-svn-branches`
    git_branches=`git branch`

    # Check each remote branch
    for branch in $svn_branches ; do
        found=`echo $branch | grep -P $1`
        # If it matches, remove it
        if [[ -n $found ]]; then
            if [[ "$2" == "-f" ]]; then
                git branch -D -r $branch
            else
                echo "Would remove remote branch $branch"
            fi
        fi
    done

    # Check each git branch
    for branch in $git_branches ; do
        found=`echo $branch | grep -P $1`
        # If it matches, remove it
        if [[ -n $found ]]; then
            if [[ "$2" == "-f" ]]; then
                git branch -D $branch
            else
                echo "Would remove branch $branch"
            fi
        fi
    done

    # If this was only a dry run, indicate how to actually prune
    if [[ "$2" != "-f" && "$2" != "-q" ]]; then
        echo "To actually remove branches, use:"
        echo "  ${FUNCNAME[0]} $1 -f"
    fi
}

# Fully convert a SVN repository into a clean git repository.
# The connection to the SVN repository is no longer available after the conversion ends.
# Interactive, the user will be promted for the URL of the SVN repository,
# whether or not to process a standard layout repository with trunk, tags and branches,
# and which authors file to use for migrating commit authors.
# Uses escape sequences for formatting the output.
function git-svn-migrate {
    repo=""
    svncontent=""
    while [[ -z $repo || -z $svncontent ]]
    do
        echo -e "Repository to convert:\033[0;32m"
        read -e -p "[URL] > " repo
        echo -n -e "\033[0m"
        echo "Analyzing repository..."
        svncontent=`svn ls --non-interactive $repo 2>/dev/null`
        if [[ -z $repo ]]
        then
            echo -e "\033[1;31mPlease specify a valid URL.\033[0m"
            echo
        elif [[ -z $svncontent ]]
        then
            echo -e "\033[1;31mRepository \033[4m$repo\033[0;1;31m does not exist.\033[0m"
            echo
        fi
    done

    # Check if it has branches and tags
    stdlayout=n
    if [[ `echo $svncontent | grep trunk/` ]]
    then
        stdlayout=y
        echo -e "Standard layout detected. Process tags and branches?\033[0;32m"
        read -e -p "[Y|n] > " stdlayout
        echo -n -e "\033[0m"
    fi

    authors="help"
    while [[ -n `echo help | grep -i "^$authors"` && -n $authors ]]
    do
        echo
        echo -e "Authors file to use: (leave empty if no authors file should be used)\033[0;32m"
        read -e -p "[filename|help] > " authors
        echo -n -e "\033[0m"
        if [[ -n `echo help | grep -i "^$authors"` && -n $authors ]]
        then
            echo
            echo "The authors file consists of a list of user name mappings, in the format:"
            echo "svn-username = Full Name <email@addr.es>"
            echo "For example:"
            echo
            echo "jdoe = John Doe <john.doe@company.net>"
            echo "gfawkes = Guy Fawkes <guy.fawkes@company.net>"
            echo
            echo -e "\033[1;31mWarning! The migration will fail if the provided authors file doesn't contain a valid entry for one of the authors found in the SVN repository.\033[0m"
        fi
    done

    summary="Migrating \033[4;1;37m$repo\033[0m"
    cmd="git svn clone"
    if [[ $stdlayout != 'n' ]]
    then
        summary="$summary with tags and branches"
        cmd="$cmd --stdlayout"
    fi
    if [[ -n $authors ]]
    then
        summary="$summary, using \033[1;37m$authors\033[0m to convert commit authors"
        cmd="$cmd --authors-file=$authors"
    fi
    cmd="$cmd $repo ."

    echo
    echo -e $summary
    echo -e "\033[1;31mWarning! The new git repository will be created in the current directory.\033[0m"
    echo -e "Proceed?\033[0;32m"
    read -e -p "[Y|n] > " go
    echo -n -e "\033[0m"
    if [[ $go == "n" ]]
    then
        echo "Aborting"
        return
    fi

    # Let's go!
    echo
    echo -e "\033[1;32mStep 1/5:\033[0;32m Fetching commit data\033[0m"
    $cmd || { echo -e "\033[1;31mFailed.\033[0m" ; return 1 ; }

    echo
    echo -e "\033[1;32mStep 2/5:\033[0;32m Cleaning up fake branches\033[0m"
    git-svn-prune-remotes -f
    if [[ $stdlayout != "n" ]]
    then
        git branch -d -r trunk
    fi

    echo
    echo -e "\033[1;32mStep 3/5:\033[0;32m Converting tags and branches\033[0m"
    git-svn-convert-tags
    git-svn-convert-branches

    echo
    echo -e "\033[1;32mStep 4/5:\033[0;32m Removing temporary data\033[0m"
    rm -rf .git/svn
    git config --remove-section svn-remote.svn

    echo
    echo -e "\033[1;32mStep 5/5:\033[0;32m Garbage collection\033[0m"
    git gc --aggressive --prune

    echo
    echo -e "\033[1;32mAll done!\033[0m"
}
