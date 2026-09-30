# The local development image's QA console uses a regular login account.
case $- in
    *i*)
        if [ "$(tty 2>/dev/null)" = /dev/ttyS0 ]; then
            printf 'NEKO_ARCH_READY\n'
        fi
        ;;
esac
