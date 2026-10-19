# git-ff-merge-pr

## Description

Merge a branch's open pull request by fast-forwarding its base branch and pushing it.

GitHub's merge buttons each make a new commit: a merge commit, a squashed commit, or rebased copies. None of them are the commits which were pushed, and none carry their signatures. Fast-forwarding puts the pushed commits themselves on the base branch, and GitHub, seeing the pull request's head commit there, marks the pull request merged.

## Installation

```shell
$ brew tap thoran/tap
$ brew install git-ff-merge-pr
```

## Dependencies

- gh, signed in.

## Usage

Open the pull request in the usual way, with gh or on GitHub:

```shell
$ gh pr create --fill
```

When it is ready to merge, from the branch:

```shell
$ git ff-merge-pr
```

It stops, pushing nothing, where:

- there is no remote called origin;
- the branch has no open pull request;
- the branch has commits which haven't been pushed, so that the pull request's head isn't the branch;
- the base branch has moved on since the branch was cut, which wants the branch rebased and pushed again;
- the local base branch has commits of its own.

Each time it says what to do about it.

To delete the branch as well, locally and on origin, once it is merged:

```shell
$ git ff-merge-pr -d
```

Before deleting anything it checks that origin's base branch holds the branch's head commit, and waits for GitHub to mark the pull request merged, since deleting the head branch before then can leave the pull request closed rather than merged. Where either check fails, it keeps the branch. Where the branch on origin is already gone, as when GitHub deletes head branches itself, it deletes only the local branch.

## Notes

1. It fetches from, and pushes to, the remote called origin.
2. The base branch is the pull request's, which is usually, but not necessarily, the default branch.
3. The local branch is deleted with `git branch -d`, so git refuses where it holds anything the base branch doesn't.

## Contributing

1. Fork it... `https://github.com/thoran/git-ff-merge-pr/fork`
2. Create your feature branch... `git checkout -b my-new-feature`
3. Commit your changes... `git commit -am 'Add some feature'`
4. Push to the branch... `git push origin my-new-feature`
5. Create a new pull request


## License

MIT
