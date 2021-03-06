#!/bin/sh
# -*- indent-tabs-mode: nil; sh-basic-offset: 4; sh-indentation: 4 -*-

script_base_dir=`dirname $0`
GPG_UID=$1

if [ $# != 2 ]; then
    echo "Usage: $0 GPG_UID CODE_NAMES"
    echo " e.g.: $0 1BD22CD1 'lenny hardy lucid'"
    exit 1
fi

CODE_NAMES=$2

run()
{
    "$@"
    if test $? -ne 0; then
        echo "Failed $@"
        exit 1
    fi
}

for code_name in ${CODE_NAMES}; do
    case ${code_name} in
        jessie|stretch|unstable)
            distribution=debian
            ;;
        *)
            distribution=ubuntu
            ;;
    esac
    for status in stable development; do
        release=${distribution}/${status}/dists/${code_name}/Release
        rm -f ${release}.gpg
        gpg --sign -ba -o ${release}.gpg -u ${GPG_UID} ${release}
    done;
done
