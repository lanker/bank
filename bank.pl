#!/usr/bin/perl

use strict;
use WWW::Mechanize;
use DBI;

# config
my $USERNAME = '';
my $PASSWORD = '';
my $DEPTH = 2;
my $LOG = 0;
my $ACCOUNT_ID = 0;
# end of config

my $url_login = 'https://mobilbank.swedbank.se/banking/swedbank/login.html';
my $url_account = 'https://mobilbank.swedbank.se/banking/swedbank/account.html?id=' . $ACCOUNT_ID;

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
    $mech->set_fields('_csrf_token' => $csrf_token, 'xyz' => $USERNAME, 'zyx' => $PASSWORD);
    my $response = $mech->submit();
}

sub get_account_transactions
{
    my @transactions;
    my $i = 0;
    $mech->get($url_account);
    my @content = split(/\n/, $mech->content());
    my @sub_transactions = parse_content(@content);
    @transactions = (@transactions, @sub_transactions);
    while ($i < $DEPTH && $mech->follow_link(class => 'trans-next') != undef)
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
    my $date;
    my $subject;
    my $amount;
    my @result;
    foreach my $l (@content)
    {
        if ($l =~ m/.*trans-date\">([^<]+)<\/div>.*/)
        {
            $date = $1;
            $date =~ s/^\s+|\s+$//g ;
            $date =~ s/([\d][\d])-([\d][\d])-([\d][\d])/20$1$2$3/;
        }
        elsif ($l =~ m/.*?trans-subject\">([^<]+)<\/div>.*/)
        {
            $subject = lc($1);
            $subject =~ s/&ouml;/ö/g;
            $subject =~ s/&aring;/å/g;
            $subject =~ s/&auml;/ä/g;
            $subject =~ s/&amp;/&/g;
            $subject =~ s/^\s+|\s+$//g ;
        }
        elsif ($l =~ m/.*?trans-amount\">([^<]+)<\/div>.*/)
        {
            $amount = $1;
            $amount =~ s/^\s+|\s+$//g ;
            $amount =~ s/\s+//g;
            if (!($subject =~ /skyddat belopp/))
            {
                @result = (@result, [$date, $subject, $amount]);
            }
            $date = 'ERROR';
            $subject = 'ERROR';
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
    my $subject;
    my $amount;
    my $sth = $dbh->prepare('SELECT * FROM swedbank ORDER BY id DESC LIMIT 1')
        or die "Couldn't prepare statement: " . $dbh->errstr;;
    $sth->execute();
    ($id, $date, $subject, $amount) = $sth->fetchrow_array;
    my $i = 0;
    foreach my $t (@transactions)
    {
        if ($t->[0] == $date && $t->[1] eq $subject && $t->[2] == $amount)
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

login();
my @transactions = get_account_transactions();
save_transactions(@transactions);

