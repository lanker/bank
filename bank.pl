#!/usr/bin/perl

package Bank;
use strict;
use Module::Pluggable require => 1;
use DBI;

##################### config
# enables some logging
my $LOG = 1;
##################### /config

my $dbh = DBI->connect("dbi:SQLite:bank.db") || die "Cannot connect: $DBI::errstr";

my @banks = plugins;
foreach my $bank (@banks)
{
    my $name = '';
    if ($bank->can('get_name'))
    {
        $name = $bank->get_name();
        if ($LOG == 1)
        {
            print "$name\n";
        }
    }
    if ($bank->can('get_transactions'))
    {
        my @transactions = $bank->get_transactions();
        if ($LOG == 1)
        {
            print "found\n";
            log_transaction(\@transactions);
        }
        save_transactions($name, \@transactions);
    }
    if ($bank->can('get_fund_value'))
    {
        my $fund_value = $bank->get_fund_value();
        save_fund($name, $fund_value);
        if ($LOG == 1)
        {
            print "fund value: $fund_value\n";
        }
    }
    if ($bank->can('get_balance'))
    {
        my $balance = $bank->get_balance();
        save_balance($name, $balance);
        if ($LOG == 1)
        {
            print "balance: $balance\n";
        }
    }
}

sub remove_saved
{
    my @transactions = @_;
    my $id;
    my $date;
    my $receiver;
    my $amount;
    my $sth = $dbh->prepare('SELECT * FROM transactions ORDER BY date DESC, id DESC LIMIT 1')
        or die "Couldn't prepare statement: " . $dbh->errstr;;
    $sth->execute();
    ($id, $date, $receiver, $amount) = $sth->fetchrow_array;
    my $i = 0;
    foreach my $t (@transactions)
    {
        if ($t->[0] == $date && $t->[1] eq $receiver && $t->[2] == $amount)
        {
            return @transactions[0..$i-1];
            last;
        }
        $i++;
    }
    return @transactions;
}

sub save_transactions
{
    my $bank_name = shift;
    my $transactions_ref = shift;
    my @transactions = @$transactions_ref;
    @transactions = remove_saved(@transactions);
    if ($LOG == 1)
    {
        print "inserting\n";
        log_transaction(\@transactions);
    }
    @transactions = reverse(@transactions);
    my $sth = $dbh->prepare("INSERT INTO transactions VALUES(NULL, ?, ?, ?, \'$bank_name\')")
        or die "Couldn't prepare statement: " . $dbh->errstr;;
    foreach my $t (@transactions)
    {
        $sth->execute($t->[0], $t->[1], $t->[2]);
    }
}

sub save_balance
{
    my $bank_name = shift;
    my $balance = shift;

    my ($s, $i, $h, $d, $m, $y, $wd, $yd, $dst) = localtime();
    my $date = sprintf("%4d%02d%02d", $y + 1900, $m + 1, $d);

    $dbh->do("INSERT INTO balance VALUES(NULL, ?, ?, \'$bank_name\')", undef, $date, $balance)
        or die "Couldn't save balance: " . $dbh->errstr;;
}

sub save_fund
{
    my $bank_name = shift;
    my $value = shift;

    my ($s, $i, $h, $d, $m, $y, $wd, $yd, $dst) = localtime();
    my $date = sprintf("%4d%02d%02d", $y + 1900, $m + 1, $d);

    $dbh->do("INSERT INTO fund VALUES(NULL, ?, ?, \'$bank_name\')", undef, $date, $value)
        or die "Couldn't save fund: " . $dbh->errstr;;
}

sub log_transaction
{
    my $transactions_ref = shift;
    my @transactions = @$transactions_ref;
    foreach my $t (@transactions)
    {
        print $t->[0] . ": " . $t->[1] . ", " . $t->[2] . "\n";
    }
}
