#!/bin/sh
# -*- indent-tabs-mode: nil; sh-basic-offset: 4; sh-indentation: 4 -*-

script_base_dir=`dirname $0`

if [ $# != 3 ]; then
    echo "Usage: $0 PROJECT_NAME PACKAGE_NAME CODE_NAMES"
    echo " e.g.: $0 'milter manager' 'milter-manager' 'lenny unstable hardy lucid'"
    exit 1
fi

PROJECT_NAME=$1
PACKAGE_NAME=$2
CODE_NAMES=$3

run()
{
    "$@"
    if test $? -ne 0; then
        echo "Failed $@"
        exit 1
    fi
}

update_repository()
{
    distribution=$1
    code_name=$2
    component=$3

    mkdir -p dists/${code_name}/${component}/binary-i386/
    mkdir -p dists/${code_name}/${component}/binary-amd64/
    mkdir -p dists/${code_name}/${component}/source/

    cat <<EOF > .htaccess
Options +Indexes
EOF

    cat <<EOF > dists/${code_name}/${component}/binary-i386/Release
Archive: ${code_name}
Component: ${component}
Origin: The ${PROJECT_NAME} project
Label: The ${PROJECT_NAME} project
Architecture: i386
EOF

    cat <<EOF > dists/${code_name}/${component}/binary-amd64/Release
Archive: ${code_name}
Component: ${component}
Origin: The ${PROJECT_NAME} project
Label: The ${PROJECT_NAME} project
Architecture: amd64
EOF

    cat <<EOF > dists/${code_name}/${component}/source/Release
Archive: ${code_name}
Component: ${component}
Origin: The ${PROJECT_NAME} project
Label: The ${PROJECT_NAME} project
Architecture: source
EOF

cat <<EOF > generate-${code_name}.conf
Dir::ArchiveDir ".";
Dir::CacheDir ".";
TreeDefault::Directory "pool/${code_name}/${component}";
TreeDefault::SrcDirectory "pool/${code_name}/${component}";
Default::Packages::Extensions ".deb";
Default::Packages::Compress ". gzip bzip2";
Default::Sources::Compress ". gzip bzip2";
Default::Contents::Compress "gzip bzip2";

BinDirectory "dists/${code_name}/${component}/binary-i386" {
  Packages "dists/${code_name}/${component}/binary-i386/Packages";
  Contents "dists/${code_name}/Contents-i386";
  SrcPackages "dists/${code_name}/${component}/source/Sources";
};

BinDirectory "dists/${code_name}/${component}/binary-amd64" {
  Packages "dists/${code_name}/${component}/binary-amd64/Packages";
  Contents "dists/${code_name}/Contents-amd64";
  SrcPackages "dists/${code_name}/${component}/source/Sources";
};

Tree "dists/${code_name}" {
  Sections "${component}";
  Architectures "i386 amd64 source";
};
EOF
    apt-ftparchive generate generate-${code_name}.conf
    chmod 644 dists/${code_name}/Contents-*

    rm -f dists/${code_name}/Release*
    rm -f *.db
    cat <<EOF > release-${code_name}.conf
APT::FTPArchive::Release::Origin "The ${PROJECT_NAME} project";
APT::FTPArchive::Release::Label "The ${PROJECT_NAME} project";
APT::FTPArchive::Release::Architectures "i386 amd64";
APT::FTPArchive::Release::Codename "${code_name}";
APT::FTPArchive::Release::Suite "${code_name}";
APT::FTPArchive::Release::Components "${component}";
APT::FTPArchive::Release::Description "${PACKAGE_NAME} packages";
EOF
    apt-ftparchive -c release-${code_name}.conf \
        release dists/${code_name} > /tmp/Release
    mv /tmp/Release dists/${code_name}
}

for code_name in ${CODE_NAMES}; do
    case ${code_name} in
        jessie|stretch|unstable)
            distribution=debian
            component=main
            ;;
        *)
            distribution=ubuntu
            component=universe
            ;;
    esac
    for status in stable development; do
        mkdir -p ${distribution}/${status}
        (cd ${distribution}/${status} &&
            update_repository $distribution $code_name $component)
    done
done
