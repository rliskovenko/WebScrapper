#!/usr/bin/perl

use common::sense;

use URI;
use URI::Escape;
use JSON;
use Web::Scraper;
use Data::Dumper;

# Pages with the list of shows
my @showlist_urls = (
    "http://animal.discovery.com/tv/tv-shows.html",
    "http://animal.discovery.com/tv/tv-shows-tab-02.html"
    );

my $BASE_URI = 'http://animal.discovery.com/';

# ?num=24&page=0&filter=clip%2Cplaylist%2Cfullepisode&tpl=dds%2Fmodules%2Fvideo%2Fall_assets_grid.html&feedGroup=video
# Order is important
my $episodes_additional_options = '?num=24&page=0&filter=clip%2Cplaylist%2Cfullepisode&tpl=dds%2Fmodules%2Fvideo%2Fall_assets_grid.html&feedGroup=video';

# Get list of shows

my $showlist_scraper = scraper {
    process "ul li #list-item", "shows[]" => sub {
        my $show_data = shift;
        my $show_info_scraper = scraper {
            process "#list-image a", show_title => '@title';
            process "#list-image a", link_to_show => sub {
                    my $tag = shift;
                    return URI->new_abs( $tag->attr('href'), $BASE_URI );
                };
            process "#list-image img", show_thumb => sub {
                    my $tag = shift;
                    return URI->new_abs( $tag->attr('src'), $BASE_URI );
                };
            process "#list-text", show_desc => 'TEXT';
            process "#list-image a", episodes => sub {
                    # Collect series
                    my $tag = shift;
                    my $episode_list_url = URI->new_abs( $tag->attr('href'), $BASE_URI );
                    my $episodes_url_scraper = scraper {
                        process "#all-videos .module-videos-all", episodes_url => '@data-service-uri';
                    };
                    my $res = $episodes_url_scraper->scrape( $episode_list_url );
                    return
                        unless $res->{episodes_url};
                    my $episodes_list_url = URI->new_abs( $res->{episodes_url}, $BASE_URI );

                    return { episode => $episodes_list_url };
                };
        };
        return $show_info_scraper->scrape( $show_data );
    }
};

## MAIN

sub _scrape {
    foreach my $url ( @showlist_urls ) {
        my $res = $showlist_scraper->scrape( URI->new( $url ) );
        print Dumper($res)."\n";
    }

}

_scrape();

exit();