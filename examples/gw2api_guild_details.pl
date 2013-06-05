#!perl -w

use strict;

use CGI;
use GW2API;

my $api = GW2API->new;

$api->emblem_texture_folder("C:/Users/ttauer/Pictures/GW2");
$api->emblem_output_folder("C:/Users/ttauer/Documents/scripts/GW2API/guild emblems");

my $q = CGI->new;

my @prior_ids = ();

# Read in guild IDs that have already been processed.
if (-e "guild_details.csv") {
  print "Reading known guilds from guild_details.csv...\n";
  open (IMAIN, "guild_details.csv") or die "unable to open file: $!\n";

  <IMAIN>; # throw out the header row

  while (<IMAIN>) {
    my ($id) = split(/\|/, $_);
    push @prior_ids, $id;
  }

  close (IMAIN);
}

open(OMAIN, ">guild_details.csv") or die "unable to open file: $!\n";

print OMAIN "guild_id|guild_name|guild_tag|emblem_bg|emblem_bg_color|emblem_fg|emblem_fg_color1|emblem_fg_color2|flags\n";

open(OHTML, ">guild_details.html") or die "unable to open file: $!\n";

print OHTML $q->start_html();
print OHTML $q->start_table();
print OHTML $q->Tr(
  $q->th("Guild ID"),
  $q->th("Guild Name"),
  $q->th("Tag"),
  $q->th("Emblem")
);

# Get a list of all guild IDs that are currently claiming an objective
print "Getting all guilds that currently control WvW objectives...\n";
my @current_guilds;
foreach my $match ($api->wvw_matches) {
  my %match_details = $api->wvw_match_details($match->{wvw_match_id});
  foreach my $map (@{$match_details{maps}}) {
    foreach my $objective (@{$map->{objectives}}) {
      push @current_guilds, $objective->{owner_guild} if defined($objective->{owner_guild});
    }
  }
}
# Merge with our prior list
print "Merging prior and current guild lists...\n" if scalar(@prior_ids) > 0;
my @known_guilds = (@prior_ids, @current_guilds);

# Dedupe the list
@known_guilds = keys %{{ map { $_ => 1 } @known_guilds }};

my $i = 0;
print "Parsing all guild details...\n";
foreach my $guild_id (@known_guilds) {
  my %guild_details = $api->guild_details($guild_id);

  my $guild_name    = $guild_details{guild_name};
  my $guild_tag     = $guild_details{tag};

  # Some guilds don't have emblems!
  my $emblem_bg         = $guild_details{emblem}->{background_id} || "";
  my $emblem_bg_color   = $guild_details{emblem}->{background_color_id} || "";
  my $emblem_fg         = $guild_details{emblem}->{foreground_id} || "";
  my $emblem_fg_color1  = $guild_details{emblem}->{foreground_primary_color_id} || "";
  my $emblem_fg_color2  = $guild_details{emblem}->{foreground_secondary_color_id} || "";
  my $emblem_flags      = $guild_details{emblem}->{flags} || [];

  print OMAIN "$guild_id|$guild_name|$guild_tag|$emblem_bg|$emblem_bg_color|$emblem_fg|$emblem_fg_color1|$emblem_fg_color2"
            . "|" . join(",", @$emblem_flags)
            . "\n";

  # Generate guild emblems
  if ($emblem_fg ne "") {
    $api->anetcolor->generate_guild_emblem(%guild_details);
#    system("perl C:\\Users\\ttauer\\Documents\\GitHub\\GW2API.pm\\examples\\gw2api_colorize_emblem.pl $guild_id")
#      == 0 or die "emblem generation failed for guild_id [$guild_id]\n";
  }

  print OHTML $q->Tr(
    $q->td($guild_id),
    $q->td($guild_name),
    $q->td($guild_tag),
    $q->td( $emblem_fg eq "" ? "No emblem" : $q->img({src=>"guild emblems/$guild_id.png"}) )
  );

  print "$i\n" if ++$i % 25 == 0;
}

close (OMAIN);

exit;

