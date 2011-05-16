#!/usr/bin/perl

use strict;
use WWW::Mechanize;
use DBI;

##################### config
my $USERNAME = '';
my $PASSWORD = '';
# how many 'next-page' to fetch
my $DEPTH = 2;
# enables some logging
my $LOG = 0;
# which account to fetch
my $ACCOUNT_ID = 0;
##################### /config

my $url_login = 'https://mobilbank.swedbank.se/banking/swedbank/login.html';
my $url_login_next = 'https://mobilbank.swedbank.se/banking/swedbank/loginNext.html';
my $url_account = 'https://mobilbank.swedbank.se/banking/swedbank/account.html?id=' . $ACCOUNT_ID;
my $url_overview = 'https://mobilbank.swedbank.se/banking/swedbank/account.html';

my $mech = WWW::Mechanize->new();
my $csrf_token;
my $dbh = DBI->connect("dbi:SQLite:swedbank.db") || die "Cannot connect: $DBI::errstr";

sub login
{
    $mech->get($url_login);
    my $content = $mech->response()->content();
    foreach my $l ($content)
    {
        if ($l =~ /.*_csrf_token.*value=\"(.+)\"/)
        {
            $csrf_token = $1;
        }
    }
    $mech->form_number(1);
    $mech->set_fields('_csrf_token' => $csrf_token, 'auth-mode' => 'code', 'xyz' => $USERNAME);
    my $response = $mech->submit();

    # password screen
    $content = $mech->response()->content();
    foreach my $l ($content)
    {
        if ($l =~ /.*_csrf_token.*value=\"(.+)\"/)
        {
            $csrf_token = $1;
        }
    }
    $mech->form_number(1);
    $mech->set_fields('_csrf_token' => $csrf_token, 'zyx' => $PASSWORD);
    $response = $mech->submit();
}

sub get_account_content
{
    $mech->get($url_account);
    return split(/\n/, $mech->content());
}

sub get_account_transactions
{
    my @transactions;
    my $i = 0;
    my @content = @_;
    my @sub_transactions = parse_content(@content);
    @transactions = (@transactions, @sub_transactions);
    while ($i < $DEPTH && $mech->follow_link(class => 'trans-next orangered') != undef)
    {
        @content = split(/\n/, $mech->content());
        @sub_transactions = parse_content(@content);
        @transactions = (@transactions, @sub_transactions);
        $i++;
    }
    if ($LOG == 1) {
        print "found\n";
        log_transaction(@transactions);
    }
    return @transactions;
}

sub parse_content
{
    my @content = @_;
    my $date = 'ERROR';
    my $receiver = 'ERROR';
    my $amount = 'ERROR';
    my @result;
    foreach my $l (@content)
    {
        if ($l =~ m/.*date\">([^<]+)<\/span>.*/)
        {
            $date = $1;
            $date =~ s/^\s+|\s+$//g ;
            $date =~ s/([\d][\d])-([\d][\d])-([\d][\d])/20$1$2$3/;
        }
        elsif ($l =~ m/.*?receiver\">([^<]+)<\/span>.*/)
        {
            $receiver = lc($1);
            $receiver =~ s/&ouml;/ö/g;
            $receiver =~ s/&aring;/å/g;
            $receiver =~ s/&auml;/ä/g;
            $receiver =~ s/&amp;/&/g;
            $receiver =~ s/^\s+|\s+$//g ;
        }
        elsif ($l =~ m/.*?amount\">([^<]+)<\/span>.*/)
        {
            $amount = $1;
            $amount =~ s/^\s+|\s+$//g ;
            $amount =~ s/\s+//g;
            if (!($receiver =~ /skyddat belopp/) &&
                $date ne 'ERROR' && $receiver ne 'ERROR' && $amount ne 'ERROR')
            {
                @result = (@result, [$date, $receiver, $amount]);
            }
            $date = 'ERROR';
            $receiver = 'ERROR';
            $amount = 'ERROR';
        }
    }
    return @result;
}

sub remove_saved
{
    my @transactions = @_;
    my $id;
    my $date;
    my $receiver;
    my $amount;
    my $sth = $dbh->prepare('SELECT * FROM swedbank ORDER BY date DESC, id DESC LIMIT 1')
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
    my @transactions = @_;
    @transactions = remove_saved(@transactions);
    if ($LOG == 1) {
        print "inserting\n";
        log_transaction(@transactions);
    }
    @transactions = reverse(@transactions);
    my $sth = $dbh->prepare("INSERT INTO swedbank VALUES(NULL, ?, ?, ?)")
        or die "Couldn't prepare statement: " . $dbh->errstr;;
    foreach my $t (@transactions)
    {
        $sth->execute($t->[0], $t->[1], $t->[2]);
    }
}

sub log_transaction
{
    my @transactions = @_;
    foreach my $t (@transactions)
    {
        print $t->[0] . ", " . $t->[1] . ", " . $t->[2] . "\n";
    }
}

sub get_account_balance
{
    my @content = @_;
    my $balance = 0;
    my $flip = 0;
    foreach my $l (@content)
    {
        if ($l =~ m/.*Tillg\. belopp.*<\/span>.*/)
        {
            $flip = 1;
        }
        if ($flip == 1 && $l =~ m/.*amount">([0-9 ]*)<\/span>.*/)
        {
            $balance = $1;
            $balance =~ s/\s+//g;
            $flip = 0;
        }
    }
    if ($LOG)
    {
        print "balance: $balance\n";
    }
    return $balance;
}

sub get_funds
{
    $mech->get($url_overview);
    my $content = $mech->response()->content();
    my @content = split(/\n/, $content);
    my $flip = 0;
    my $fund = 0;
    foreach my $l (@content)
    {
        if ($l =~ m/.*Fond.*<\/span>.*/)
        {
            $flip = 1;
        }
        if ($flip == 1 && $l =~ m/.*amount">([0-9 ]*)<\/span>.*/)
        {
            $flip = 0;
            $fund = $1;
            $fund =~ s/\s+//g;
        }
    }
    return $fund;
}

sub save_balance
{
    my $balance = $_[0];

    my ($s, $i, $h, $d, $m, $y, $wd, $yd, $dst) = localtime();
    my $date = sprintf("%4d%02d%02d", $y + 1900, $m + 1, $d);

    $dbh->do("INSERT INTO balance VALUES(NULL, ?, ?)", undef, $date, $balance)
        or die "Couldn't save balance: " . $dbh->errstr;;
}

# TODO: merge with save_balance
sub save_fund
{
    my $value = $_[0];

    my ($s, $i, $h, $d, $m, $y, $wd, $yd, $dst) = localtime();
    my $date = sprintf("%4d%02d%02d", $y + 1900, $m + 1, $d);

    $dbh->do("INSERT INTO fund VALUES(NULL, ?, ?)", undef, $date, $value)
        or die "Couldn't save fund: " . $dbh->errstr;;
}

login();
my $fund = get_funds();
save_fund($fund);
my @content = get_account_content();
my @transactions = get_account_transactions(@content);
save_transactions(@transactions);
my $balance = get_account_balance(@content);
save_balance($balance);
