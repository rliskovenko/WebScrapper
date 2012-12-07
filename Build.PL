use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'WebScrapper',
    license             => 'perl',
    dist_author         => q{Roman V. Liskovenko <rliskovenko@gmail.com>},
    dist_version_from   => 'lib/WebScrapper.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'perl' => 5.006,
    },
    add_to_cleanup      => [ 'WebScrapper-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
