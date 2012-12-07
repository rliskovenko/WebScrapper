#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'WebScrapper' ) || print "Bail out!\n";
}

diag( "Testing WebScrapper $WebScrapper::VERSION, Perl $], $^X" );
