#!/usr/bin/perl

use common::sense;

use URI;
use URI::Escape;
use JSON;
use Web::Scraper;
use Data::Dumper;

## MAIN


my @show_urls = (
        "http://animal.discovery.com/tv/tv-shows.html",
        "http://animal.discovery.com/tv/tv-shows-tab-02.html"
        );

my $show_scraper = scraper {
    process "ul li #list-item", "shows[]" => scraper {
        process "#list-image a", show_link => '@href', title => '@title';
        process "#list-image img", img_src => '@src';
        process "#list-text", description => 'TEXT';
    }
};

my $episode_url_scraper = scraper {
    process "#all-videos .module-videos-all", episodes_url => '@data-service-uri';
};

# ?num=24&page=0&filter=clip%2Cplaylist%2Cfullepisode&tpl=dds%2Fmodules%2Fvideo%2Fall_assets_grid.html&feedGroup=video
# Order is important
my $episodes_additional_options = '?num=24&page=0&filter=clip%2Cplaylist%2Cfullepisode&tpl=dds%2Fmodules%2Fvideo%2Fall_assets_grid.html&feedGroup=video';

my $episodes_scraper = scraper {
    process ".all-grid-inner .item", 'episodes[]' => scraper {
            process ".thumbnail a img", thumbnail_url => '@src';
            process ".thumbnail a .playlist-clip-count", playlist_size => 'TEXT';
            process ".details h5", show_title => 'TEXT';
            process ".details a", episode_link => '@href', title => 'TEXT';
        };
    process ".pagination li", 'pages[]' => scraper {
            process 'a', link => '@onclick', text => 'TEXT';
        };
};

my $one_episode_scraper = scraper {
    process "script", 'js[]' => sub {
        my $tmp = $_->as_HTML();
        my ( $clips_js ) = $tmp =~ /(\"clips\":\s+\[[^]]+\])/ismx;
        my $clip_data = from_json("{".$clips_js."}");
        {
            m3u => $clip_data->{clips}[0]{m3u8},
            duration => $clip_data->{clips}[0]{duration},
            thumbnail_clip => $clip_data->{clips}[0]{thumbnailURL}
        };
    };
};

sub _scrap_shows {
    my $scraper = shift;
    my $urls = shift;
    
    my @ret;
    foreach my $current_url ( @$urls ) {
        my $res = $scraper->scrape( URI->new( $current_url ) );
        foreach my $show ( @{ $res->{shows} } ) {
            push @ret, $show;
        }
    }
    return wantarray ? @ret : \@ret;
}

sub _scrap_episodes {
    my $scraper_url = shift;
    my $scraper = shift;
    my $url = shift;
    
    my @ret;
    # Get episodes url
    my $res = $scraper_url->scrape( $url );
    return wantarray ? () : []
        unless exists $res->{episodes_url};
    my $episodes_url = URI->new_abs( $res->{episodes_url}, $url );
    $episodes_url->query( $episodes_additional_options );

    # Unrolled for perfornmance
    $res = $scraper->scrape( $episodes_url );
    # Grab episodes on 1st page
    foreach my $episode ( @{ $res->{episodes} } ) {
        my $tmp = _scrap_one_episode( $one_episode_scraper, $episode->{episode_link} );
        @{ $episode }{ keys %$tmp } = values %$tmp;
        push @ret, $episode;
    }

    my $next_page;
    foreach my $page ( @{ $res->{pages} } ) {
        ( $next_page ) = $page->{link} =~ /,(\d+),/igmx
            if ( $page->{text} =~ /NEXT/igmx and $page->{link} );
    }
    
    # process pages
    while ( $next_page ) {
        # Correct a link
        my $next_page_url = $episodes_url->as_string();
        $next_page_url =~ s/page=\d+/page=$next_page/igmx;
        $next_page_url = URI->new( $next_page_url );
        
        $res = $scraper->scrape( $next_page_url );
        # Grab episodes from page
        foreach my $episode ( @{ $res->{episodes} } ) {
            my $tmp = _scrap_one_episode( $one_episode_scraper, $episode->{episode_link} );
            @{ $episode }{ keys %$tmp } = values %$tmp;
            push @ret, $episode;
        }
        
        $next_page = undef;
        foreach my $page ( @{ $res->{pages} } ) {
            ( $next_page ) = $page->{link} =~ /,(\d+),/igmx
                if ( $page->{link} and $page->{text} =~ /NEXT/igmx );
        }
    }
    
    print Dumper(\@ret)."\n";
    return wantarray ? @ret : \@ret;
}

sub _scrap_one_episode {
    my $scraper = shift;
    my $url = shift;
    
    my %ret;
    my $res = $scraper->scrape( $url );    
    foreach my $info ( @{ $res->{js} } ) {
        @ret{ keys %$info} = values %$info
            if $info->{m3u};
    }
    return wantarray ? %ret : \%ret;
}

my @scrap_results;
foreach my $show ( _scrap_shows( $show_scraper, \@show_urls ) ) {
    my $res = $show;
    print "> ".$show->{show_link}."\n";
    $res->{series} = _scrap_episodes( $episode_url_scraper, $episodes_scraper, $res->{show_link} );
    push @scrap_results, $res;
}

#print Dumper( \@scrap_results );