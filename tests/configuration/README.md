# Configuration tests

## Preparation

```
zef install Tomty
export SP6_REPO=https://sparrowhub.io/repo
```

## How to run

```
tomty --color --all --show-failed
```

Verbose output

```
tomty --verbose --all
```

Run single test

```
tomty ansible-enable-arch-multilib-repo-01
```

# See also

[Tomty](https://github.com/melezhik/Tomty)
[Sparrow6 plugins](https://github.com/melezhik/Sparrow6/blob/master/documentation/plugins.md)
