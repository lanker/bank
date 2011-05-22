#!/usr/bin/perl

# Takes a file $map_file containing lines with 'something regex' and maps
# transactions from the database that matches 'regex' to 'something' and prints
# the result.
#
# Example of a maps file:
#
# cds    (play\.com|boomkat|warp)
# petrol (statoil|shell|preem|okq8)

use strict;
use DBI;
use Getopt::Long;

my %maps;
my %values;
my $total_plus = 0;
my $total_minus = 0;
my $unmapped = 0;
my $map_file = 'maps';
my $database = 'bank.db';

my ($help, $date_filter);
usage() if (!GetOptions('help|?' => \$help, 'database=s' => \$database, 'map_file=s' => \$map_file, 'date=i' => \$date_filter)
          or defined $help );
sub usage
{
  print "Unknown option: @_\n" if ( @_ );
  print "usage: $0 [--database DATABASE] [--maps MAPS_FILE] [--date DATE (example 201104 for April 2011)] [--help|-?]\n";
  exit;
}

my $dbh = DBI->connect("dbi:SQLite:$database") || die "Cannot connect: $DBI::errstr";
sub read_maps
{
    open(FILE, "<$map_file");
    while (<FILE>)
    {
        my $line = $_;
        # skip comments
        if ($line =~ m/^#.*/)
        {
            next;
        }
        my @line = split(/\s+/, $line);
        my $key = $line[0];
        my $value = $line[1];
        $maps{$key} = $value;
    }
}

sub fetch_transaction
{
    my $arg = $_[0];
    my @trans = ();
    my $sth = $dbh->prepare('SELECT * FROM transactions ORDER BY date DESC, id DESC')
        or die "Couldn't prepare statement: " . $dbh->errstr;;
    $sth->execute();
    my $i = 0;
    while (my ($id, $date, $subject, $amount) = $sth->fetchrow_array)
    {
        if (defined $arg)
        {
            if ($date =~ m/^$arg/)
            {
                my @sub_trans = ($date, lc $subject, $amount);
                @trans = (@trans, [@sub_trans]);
                if ($amount > 0) {$total_plus  += $amount;}
                else             {$total_minus += $amount;}
            }
        }
        else
        {
            my @sub_trans = ($date, lc $subject, $amount);
            @trans = (@trans, [@sub_trans]);
            if ($amount > 0) {$total_plus  += $amount;}
            else             {$total_minus += $amount;}
        }
    }
    return @trans;
}

sub map_transaction
{
    my @trans = @_;
    foreach my $t (@trans)
    {
        my $mapped = 0;
        while (my ($key, $value) = each(%maps))
        {
            if ($t->[1] =~ m/$value/)
            {
                $values{$key} += $t->[2];
                $mapped = 1;
                #print "$date $key - $subject: $amount\n";
            }
        }
        if (!$mapped)
        {
            $unmapped += $t->[2];
        }
    }
}

sub print_values
{
    while (my ($type, $amount) = each(%values))
    {
        if ($amount < 0) {$amount = -$amount;}
        print "$type: $amount\n";
    }
    print "------------\ntotal in: $total_plus, total out: $total_minus\nunmapped: $unmapped\n";
}

my @transactions;
@transactions = fetch_transaction($date_filter);
read_maps();
map_transaction(@transactions);
print_values();
