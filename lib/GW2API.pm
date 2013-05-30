package GW2API;

use strict;
use warnings;

our $VERSION     = "0.1";

use CHI;
use JSON::XS;
use LWP::UserAgent;

use Carp ();

=pod

=head1 NAME

GW2API - An interface library for the Guild Wars 2 API

=head1 SYNOPSIS

 require GW2API;
 
 my $api = GW2API->new;
 
 # Check the current state of an event on all worlds
 
 my %event_states = $api->event_state_by_world($event_id);
 
 foreach my $world_id (keys %event_states) {
     my $state = $event_states{$world_id};
     
     print "$world_id : $state\n";
     
 }
 
 # Lookup the attribute bonuses on a weapon
 
 my %item_details = $api->item_details($item_id);
 
 my $attributes_ref = %item_details{weapon}->{attributes};
 
 foreach my $attribute (@$attributes_ref) {
     my ($attr_name, $attr_value) = 
          ($attribute->{attribute}, $attribute->{modifier});
     
     print "+$attr_value $attr_name\n";
     
 }

=head1 DESCRIPTION

GW2API is a class module that provides a set of standard interfaces to the Guild 
Wars 2 API. 

=cut

####################
# Constants
####################

# Pagenames of the available interfaces
my $_url_events           = 'events.json';
my $_url_event_names      = 'event_names.json';
my $_url_map_names        = 'map_names.json';
my $_url_world_names      = 'world_names.json';

my $_url_matches          = 'wvw/matches.json';
my $_url_match_details    = 'wvw/match_details.json';
my $_url_objective_names  = 'wvw/objective_names.json';

my $_url_items            = 'items.json';
my $_url_item_details     = 'item_details.json';

my $_url_recipes          = 'recipes.json';
my $_url_recipe_details   = 'recipe_details.json';

# Supported languages
my @_languages = qw/de en es fr/;

####################
# Constructor
####################

=pod

=head1 Constructor

=over 4

=item $api = GW2API->new
=item $api = GW2API->new( key => value, ... )

This method constructs a new C<GW2API> object and returns it. Key/value pairs of 
configuration options may be provided.

=cut

sub new {
  # Check for common user mistake
  Carp::croak("Options to GW2API should be key/value pairs, not a hash reference") 
      if ref($_[1]) eq 'HASH'; 

  my($class, %cnf) = @_;
  
=pod

=item timeout [INT]

The length of time, in seconds, to wait for a response from the API. Defaults to 30.

=cut

  my $timeout = delete $cnf{timeout};
  $timeout = 30 unless defined $timeout;
  
=pod

=item retries [INT]

The number of times to attempt an API request before dying. Defaults to 3.

=cut

  my $retries = delete $cnf{retries};
  $retries = 3 unless defined $retries;
  
=pod

=item version [STRING]

The version of the API to use. Defaults to 'v1', which is the only version 
available at this time.

=cut

  my $version = delete $cnf{version};
  $version = 'v1' unless defined $version;
  
=pod

=item language [STRING]

The language code to use for all API requests. Defaults to 'en', other supported 
languages are 'de', 'es', and 'fr'. This setting can be overridden for 
individual API methods.

=cut

  my $language = check_language(delete $cnf{language});
  $language = 'en' unless defined $language;
  
=pod

=item nocache [BOOL]

Disable local caching of API responses. Defaults to undef. Using this in 
combination with any of the following cache options will cause an error.

=cut

  my $nocache = delete $cnf{nocache};
  
=pod

=item cache_dir [STRING]

The local directory to use as the cache location. Defaults to './gw2api-cache' 
and will attempt to create the directory if it does not exist.

=cut

  my $cache_dir = delete $cnf{cache_dir};
  Carp::croak("Can't mix cache_dir and nocache")
    if $cache_dir && $nocache;
  
=pod

=item cache_age [DURATION]

Length of time after which the cached version of I<most> responses will expire. 
Defaults to '24 hours'. Accepted values are strings consisting of an integer 
followed by a time unit, e.g. '1 day' or '10 seconds'.

=cut

  my $cache_age = delete $cnf{cache_age};
  Carp::croak("Can't mix cache_age and nocache")
    if $cache_age && $nocache;
  $cache_age = "24 hours" unless defined $cache_age;
  
=pod

=item event_cache_age [DURATION]

Length of time after which the cached version of I<event state> responses will 
expire. Defaults to '30 seconds'.

=cut

  my $event_cache_age = delete $cnf{event_cache_age};
  Carp::croak("Can't mix event_cache_age and nocache")
    if $event_cache_age && $nocache;
  $event_cache_age = "30 seconds" unless defined $event_cache_age;
  
=pod

=item wvw_cache_age [DURATION]

Length of time after which the cached version of I<WvW match detail> responses 
will expire. Defaults to '5 minutes'.

=cut

  my $wvw_cache_age = delete $cnf{wvw_cache_age};
  Carp::croak("Can't mix wvw_cache_age and nocache")
    if $wvw_cache_age && $nocache;
  $wvw_cache_age = "1 minute" unless defined $wvw_cache_age;
  
  if (%cnf && $^W) {
    Carp::carp("Unrecognized GW2API options: @{[sort keys %cnf]}");
  }
  
  # Create object
  my $self  = bless {
      timeout         => $timeout,
      retries         => $retries,
      version         => $version,
      base_url        => 'https://api.guildwars2.com/' . $version,
      language        => lc($language),
      json            => JSON::XS->new,
      ua              => LWP::UserAgent->new,
      cache           => undef,
      cache_age       => $cache_age,
      event_cache_age => $event_cache_age,
      wvw_cache_age   => $wvw_cache_age,
      nocache         => $nocache,
    }, $class;
  
  # Set up file caching
  unless (defined $nocache) {
    $cache_dir = './gw2api-cache' unless defined $cache_dir;
    # If it exists...
    if ( -e $cache_dir ) {
      # ... make sure it's a directory
      if ( ! -d $cache_dir ) {
        Carp::croak "Cache_dir [$cache_dir] is not a directory";
      }
      # ... make sure it's writeable
      if ( ! -w $cache_dir ) {
        Carp::croak "Unable to write to cache_dir [$cache_dir]";
      }
    # Otherwise, attempt to create it
    } else {
      mkdir $cache_dir or Carp::croak "Failed to create cache_dir [$cache_dir]: $!\n";
    }
    $self->{cache} = CHI->new( driver => 'File', root_dir => $cache_dir );
  }
  
  return $self;
}

####################
# Core methods
####################

# Shortcuts
sub ua {
  my $self = shift;
  return $self->{ua};
}

sub json {
  my $self = shift;
  return $self->{json};
}

sub cache {
  my $self = shift;
  return $self->{cache};
}

###
# Check Language
###
# @param scalar     Input language code
#
# @return scalar    Validated language code
#
sub check_language {
  my ($self, $lang) = @_;
  
  # If input is undef, return undef
  return undef if !defined($lang);
  
  my $lang_orig = $lang;
  
  $lang = lc($lang);
  
  if ($lang ~~ @_languages) {
    return $lang;
  } else {
    Carp::croak "Language code [$lang_orig] is not supported";
  }
}

###
# API Request
###
# @param scalar     Name of JSON interface
# @param hashref    Key/value pairs of GET parameters
#
# @return scalar    Decoded JSON object
#
sub api_request {
  my ($self, $interface, $parms, $cache_age) = @_;
  
  my $parm_string = "";
  
  if ($parms) {
    my @parm_pairs;
    foreach my $k (sort keys %$parms) {  # sort necessary so that cache keys are deterministic
      push @parm_pairs, "$k=$parms->{$k}";
    }
    $parm_string = '?' . join('&', @parm_pairs)
  }
  
  my $_url = $self->{base_url} . '/' . $interface . $parm_string;
  
  my $response;

  # Check in CHI cache first
  $response = $self->cache->get($_url) unless defined $self->{nocache};
  
  if ( !defined $response ) {
    
    # If not in cache, send GET request to API
    $self->ua->timeout($self->{timeout});
    
    for (my $i = 0; $i < $self->{retries}; $i++) {
      $response = $self->ua->get($_url);
      
      if ($response->is_success()) {
        $response = $response->decoded_content();
      }
    }
    
    # If no response after using up retries, die
    die $response->status_line() if !defined $response;
    
    # Set the CHI cache for this $_url for efficient future access
    $cache_age = $self->{cache_age} unless defined $cache_age;
    $self->cache->set($_url, $response, $cache_age) unless defined $self->{nocache};
  }
  
  my $decoded = $self->json->decode ($response) || die "could not decode JSON\n";
  
  Carp::croak("Error [$decoded->{text}] returned from $interface for parameters: $parm_string")
    if ref($decoded) eq "HASH" && defined $decoded->{error};
    
  return $decoded;
}

=pod

=back

=head1 Methods

=cut

####################
# Specific API accessors
####################

=pod

=over

=item $api->event_names
=item $api->event_names( $lang )

=item $api->map_names
=item $api->map_names( $lang )

=item $api->world_names
=item $api->world_names( $lang )

=item $api->objective_names
=item $api->objective_names( $lang )

Each of these methods returns a hash, keyed by the event/map/etc. ID, containing 
the names corresponding to those IDs. An optional language parameter can be 
passed to override the default language.

=cut

sub _generic_names {
 my ($self, $interface, $lang) = @_;
  
  if (defined $lang) {
    $lang = $self->check_language($lang);
  } else {
    $lang = $self->{language};
  }
  
  my $json = $self->api_request($interface, { lang => $lang } );
  
  my $names = {};
  
  foreach my $subject (@$json) {
    my $id    = $subject->{id};
    my $name  = $subject->{name};
    
    $names->{$id} = $name;
  }
  
  return %$names;
}

sub event_names {
  my ($self, $lang) = @_;
  
  return $self->_generic_names($_url_event_names, $lang);
}

sub map_names {
  my ($self, $lang) = @_;
  
  return $self->_generic_names($_url_map_names, $lang);
}

sub world_names {
  my ($self, $lang) = @_;
  
  return $self->_generic_names($_url_world_names, $lang);
}

sub objective_names {
  my ($self, $lang) = @_;
  
  return $self->_generic_names($_url_objective_names, $lang);
}

=pod

=item $api->event_state( $event_id, $world_id )

Returns a string containing the current state of a specific event on a specific 
world. Event state will be one of the following values (definitions are from 
L<the official API documentation|https://forum-en.guildwars2.com/forum/community/api/API-Documentation/>):

 State        Meaning
 ------------ ---------------------------------------------------------
 Active       The event is running now.
 Success      The event has succeeded.
 Fail         The event has failed.
 Warmup       The event is inactive, and will only become active once
              certain criteria are met.
 Preparation  The criteria for the event to start have been met, but 
              certain activities (such as an NPC dialogue) have not 
              completed yet. After the activites have been completed, 
              the event will become Active.

=cut

sub event_state {
  my ($self, $event_id, $world_id) = @_;
  
  # Sanity checks on event_id
  Carp::croak("You must provide an event ID")
    unless defined $event_id;
  
  Carp::croak("Given event ID [$event_id] does not match event ID pattern")
    unless $event_id =~ /^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$/i;
  
  # Sanity check on world_id
  Carp::croak("Given world ID [$world_id] is not a positive integer")
    unless $world_id =~ /^\d+$/;
  
  my $json = $self->api_request($_url_events, { event_id => $event_id, world_id => $world_id }, "30 seconds" );
  
  Carp::croak("No results for event ID [$event_id] and world ID [$world_id]")
    unless @{$json->{events}} > 0;
  
  return $json->{events}->[0]->{state};
}

=pod

=item $api->event_state_by_world( $event_id )

Returns a hash, keyed by world ID, containing the current state of the given 
event on each world.

=cut

sub event_state_by_world {
  my ($self, $event_id) = @_;
  
  # Sanity checks on event_id
  Carp::croak("You must provide an event ID")
    unless defined $event_id;
  
  Carp::croak("Given event ID [$event_id] does not match event ID pattern")
    unless $event_id =~ /^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$/i;
  
  my $json = $self->api_request($_url_events, { event_id => $event_id }, "30 seconds" );
  
  Carp::croak("No results for event ID [$event_id]")
    unless @{$json->{events}} > 0;
  
  my $event_state_by_world = {};
  
  foreach my $event (@{$json->{events}}) {
    my $world_id  = $event->{world_id};
    my $state     = $event->{state};
    
    $event_state_by_world->{$world_id} = $state;
  }
  
  return %$event_state_by_world;
}

=pod

=item $api->event_states_in_map( $map_id, $world_id )

Returns a hash, keyed by event ID, containing the current state of all events 
occurring within a specific map on a specific world.

=cut

sub event_states_in_map {
  my ($self, $map_id, $world_id) = @_;
  
  # Sanity checks on map_id
  Carp::croak("You must provide a map ID")
    unless defined $map_id;
  
  Carp::croak("Given map ID [$map_id] is not a positive integer")
    unless $map_id =~ /^\d+$/;
  
  # Sanity checks on world_id
  Carp::croak("You must provide a world ID")
    unless defined $world_id;
  
  Carp::croak("Given world ID [$world_id] is not a positive integer")
    unless $world_id =~ /^\d+$/;
  
  my $json = $self->api_request($_url_events, { map_id  => $map_id, world_id => $world_id }, "30 seconds" );
  
  Carp::croak("No results for map ID [$map_id] and world ID [$world_id]")
    unless @{$json->{events}} > 0;
  
  my $event_states = {};
  
  foreach my $event (@{$json->{events}}) {
    my $event_id  = $event->{event_id};
    my $state     = $event->{state};
    
    $event_states->{$event_id} = $state;
  }
  
  return %$event_states;
}

=pod

=item $api->wvw_matches

Returns an array containing basic information on the current WvW matches. Each 
array element is a hash with the following structure:

 (
   wvw_match_id   => [STR],  # Match ID
   red_world_id   => [INT],  # World ID of the red world
   blue_world_id  => [INT],  # World ID of the blue world
   green_world_id => [INT],  # World ID of the green world
 )

=cut

sub wvw_matches {
  my ($self) = @_;
  
  my $json = $self->api_request($_url_matches);
  
  return @{$json->{wvw_matches}};
}

=pod

=item $api->wvw_match_details( $match_id )

Returns a hash containing detailed information on a specific WvW match. The hash 
has the following structure:

 (
   match_id   => [STRING],  # Match ID
   scores     =>
     [
       [INT],               # Red world total score
       [INT],               # Green world total score
       [INT]                # Blue world total score
     ],
   maps       =>            # Array of map data
     [
       {
         type       => [STRING],  # Map type (RedHome, GreenHome, BlueHome, Center)
         scores     =>
           [
             [INT],               # Red world map score
             [INT],               # Green world map score
             [INT]                # Blue world map score
           ],
         objectives =>            # Array of objectives in the map
           [
             {
               id          => [INT],    # Objective ID
               owner       => [STRING], # Current owner of the objective (Red, Blue, Green)
               owner_guild => [STRING], # Guild ID that has claimed the objective
                                        #   (only present if objective has been claimed)
             },
             ...                  # Repeat for all objectives in the map
           ]
       },
       ...                  # Repeat for each of 4 maps
     ],
 )

=cut

sub wvw_match_details {
  my ($self, $match_id) = @_;
  
  # Sanity checks on match_id
  Carp::croak("You must provide a match ID")
    unless defined $match_id;
  
  Carp::croak("Given match ID [$match_id] is invalid")
    unless $match_id =~ /^[12]-[1-9]$/i;
  
  my $json = $self->api_request($_url_match_details, { match_id => $match_id }, "5 minutes" );
  
  return %$json;
}

=pod

=item $api->items

Returns an array containing all known item IDs.

=cut

sub items {
  my ($self) = @_;
  
  my $json = $self->api_request($_url_items);
  
  return @{$json->{items}};
}

=pod

=item $api->item_details( $item_id )
=item $api->item_details( $item_id, $lang )

Returns a hash containing detailed information for the given item ID. An 
optional language parameter can be passed to override the default language. The 
hash has the following structure (elements marked with *** are enumerated below 
the main structure):

 (
   item_id      => [INT],           # Item ID
   name         => [STRING],        # Item name
   description  => [STRING],        # Item description
   type         => [STRING],        # Item type***
   level        => [INT],           # Required level
   rarity       => [STRING],        # Rarity***
   vendor_value => [INT],           # Value when sold to a merchant
   game_types   => @([STRING],...), # Game types where item can be used***
   flags        => @([STRING],...), # Behavioral flags***
   restrictions => @([STRING],...), # Racial restrictions***
   
   # One of the following data elements corresponding to the value of "type" above.
   # Note that some item types do not have a corresponding data element.
   
   armor =>
     {
       type           => [STRING],  # Armor type***
       weight_class   => [STRING],  # Armor weight class (Light, Medium, Heavy)
       defense        => [INT],     # Defense value
       infusion_slots => @( ),      # Infusion slots***
       infix_upgrade  => %( ),      # Infix upgrade***
       suffix_item_id => [INT],     # Item ID of attached upgrade component
     }
   
   back =>
     {
       infusion_slots => @( ),      # Infusion slots***
       infix_upgrade  => %( ),      # Infix upgrade***
       suffix_item_id => [INT],     # Item ID of attached upgrade component
     }
   
   bag =>
     {
       no_sell_or_sort => [BOOL],   # Items in bag are not sorted or shown to merchants
       size            => [INT],    # Number of slots
     }
   
   consumable =>
     {
       type         => [STRING],    # Consumable type***
       duration_ms  => [INT],       # Duration of nourishment effect
       description  => [STRING],    # Description of nourishment effect
                                    # (Nourishment effects are only on Food and Utility consumables)
     }
   
   container =>
     {
       type => [STRING],            # Container type (Default, GiftBox)
     }
   
   gathering =>
     {
       type => [STRING],            # Gathering type (Foraging, Logging, Mining)
     }
   
   gizmo =>
     {
       type => [STRING],            # Gizmo type (Default, RentableContractNpc, UnlimitedConsumable)
     }
   
   tool =>
     {
       type => [STRING],            # Tool type (Salvage)
     }
   
   trinket =>
     {
       type => [STRING],            # Trinket type (Accessory, Amulet, Ring)
       infusion_slots => @( ),      # Infusion slots***
       infix_upgrade  => %( ),      # Infix upgrade***
       suffix_item_id => [INT],     # Item ID of attached upgrade component
     }
   
   upgrade_component =>
     {
       type           => [STRING],        # Upgrade type (Default, Gem, Rune, Sigil)
       flags          => @([STRING],...), # Upgrade flags***
       infusion_upgrade_flags => @([STRING],...), # Infusion flags (Defense, Offense, Utility)
       infix_upgrade  => %( ),            # Infix upgrade***
       suffix         => [STRING],        # Suffix bestowed by the upgrade
     }
   
   weapon =>
     {
       type        => [STRING],     # Weapon type***
       damage_type => [STRING],     # Damage type (Physical, Fire, Ice, Lightning)
       min_power   => [INT],        # Minimum weapon strength value
       max_power   => [INT],        # Maximum weapon strength value
       defense     => [INT],        # Defense value
       infusion_slots => @( ),      # Infusion slots***
       infix_upgrade  => %( ),      # Infix upgrade***
       suffix_item_id => [INT],     # Item ID of attached upgrade component
     }
 )

The following elements are shared between different type data elements:

 infusion_slots =>
   [
     {
       flags  => @([STRING]...),  # Flags on the infusion slot (Defense, Offense, Utility)
       item   => [INT],           # Item ID of attached infusion
     }
   ]

 infix_upgrade =>
   {
     buff       =>
       {
         skill_id     => [INT],     # Skill ID of the infixed buff skill
         description  => [STRING],  # Description of the infixed buff skill
       },
     attributes =>
       [
         {
           attribute  => [STRING],  # Attribute name
                                    #   (ConditionDamage, CritDamage, Healing,
                                    #    Power, Precision, Toughness, Vitality)
           modifier   => [INT],     # Value of attribute bonus
         },
         ...                        # Repeat for each attribute
       ]
   }

Enumerations:

=over

=item Item type

 Armor
 Back
 Bag
 Consumable
 Container
 CraftingMaterial
 Gathering
 Gizmo
 MiniPet
 Tool
 Trinket
 Trophy
 UpgradeComponent
 Weapon

=item Rarity

 Junk
 Basic
 Fine
 Masterwork
 Rare
 Exotic
 Ascended
 Legendary

=item Game types

 Activity
 Dungeon
 Pve
 Pvp
 PvpLobby
 Wvw

=item Flags

 AccountBound
 HideSuffix
 NoMysticForge
 NoSalvage
 NoSell
 NotUpgradeable
 NoUnderwater
 SoulBindOnAcquire
 SoulBindOnUse
 Unique

=item  Restrictions

 Asura
 Charr
 Human
 Norn
 Sylvari

*NOTE: There is a single item with restrictions of ('Guardian', 'Warrior'); this is probably a mistake in the API build.

=item Armor type

 Boots
 Coat
 Gloves
 Helm
 HelmAquatic
 Leggings
 Shoulders

=item Consumable type

 AppearanceChange
 ContractNpc
 Food
 Generic
 Halloween
 Immediate
 Transmutation
 Unlock
 Utility

=item Upgrade component flags

 # Armor
 HeavyArmor
 LightArmor
 MediumArmor
 
 # Weapons
 Axe
 LongBow
 ShortBow
 Dagger
 Focus
 Greatsword
 Hammer
 Harpoon
 Mace
 Pistol
 Rifle
 Scepter
 Shield
 Speargun
 Staff
 Sword
 Torch
 Trident
 Warhorn
 
 # Trinkets
 Trinket

=item Weapon type

 Axe
 Dagger
 Focus
 Greatsword
 Hammer
 Harpoon
 LongBow
 Mace
 Pistol
 Rifle
 Scepter
 Shield
 ShortBow
 Speargun
 Staff
 Sword
 Torch
 Toy
 Trident
 TwoHandedToy
 Warhorn

=back

=cut

sub item_details {
  my ($self, $item_id, $lang) = @_;
  
  # Sanity checks on item_id
  Carp::croak("You must provide an item ID")
    unless defined $item_id;
  
  Carp::croak("Given item ID [$item_id] is not a positive integer")
    unless $item_id =~ /^\d+$/;
  
  if (defined $lang) {
    $lang = $self->check_language($lang);
  } else {
    $lang = $self->{language};
  }
  
  my $json = $self->api_request($_url_item_details, { lang => $lang, item_id => $item_id } );
  
  return %$json;
}

=pod

=item $api->recipes

Returns an array containing all known recipe IDs.

=cut

sub recipes {
  my ($self) = @_;
  
  my $json = $self->api_request($_url_recipes);
  
  return @{$json->{recipes}};
}

=pod

=item $api->recipe_details( $recipe_id )
=item $api->recipe_details( $recipe_id, $lang )

Returns a hash containing detailed information for the given recipe ID. An 
optional language parameter can be passed to override the default language. The 
hash has the following structure:

 (
   recipe_id          => [INT],     # Recipe ID
   type               => [STRING],  # Recipe type***
   output_item_id     => [INT],     # Item ID of the recipe output
   output_item_count  => [INT],     # Quantity of item output
   min_rating         => [INT],     # Required rating in the associated crafting discipline
   time_to_craft_ms   => [INT],     # Duration of crafting the recipe
   ingredients        =>
     [
       {
         item_id  => [INT],           # Item ID of the ingredient
         count    => [INT],           # Required quantity of the ingredient
       },
       ...                            # Repeat for each ingredient, up to 4
     ],
 )

=cut

sub recipe_details {
  my ($self, $recipe_id) = @_;
  
  # Sanity checks on recipe_id
  Carp::croak("You must provide a recipe ID")
    unless defined $recipe_id;
  
  Carp::croak("Given recipe ID [$recipe_id] is not a positive integer")
    unless $recipe_id =~ /^\d+$/;
  
  my $json = $self->api_request($_url_recipe_details, { recipe_id => $recipe_id } );
  
  return %$json;
}

=pod

=back

=head1 Author

Tony Tauer, E<lt>dr.ishmael[at]gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2013 by Tony Tauer

This library is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself. 

=cut

1;