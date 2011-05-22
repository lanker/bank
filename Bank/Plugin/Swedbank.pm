#!/usr/bin/perl

package Bank::Plugin::Swedbank;

use strict;
use WWW::Mechanize;

##################### config
my $USERNAME = '';
my $PASSWORD = '';
# how many 'next-page' to fetch
my $DEPTH = 2;
# which account to fetch
my $ACCOUNT_ID = 0;
##################### /config

my $url_login = 'https://mobilbank.swedbank.se/banking/swedbank/login.html';
my $url_login_next = 'https://mobilbank.swedbank.se/banking/swedbank/loginNext.html';
my $url_account = 'https://mobilbank.swedbank.se/banking/swedbank/account.html?id=' . $ACCOUNT_ID;
my $url_overview = 'https://mobilbank.swedbank.se/banking/swedbank/account.html';

my $mech = WWW::Mechanize->new();
my $csrf_token;
my $logged_in = 0;

sub get_name
{
    return 'swedbank';
}

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
    $logged_in = 1;
}

sub get_account_content
{
    $mech->get($url_account);
    return split(/\n/, $mech->content());

    ##$mech->save_content('test.htm');
    #open(FILE, '<test.htm');
    #my @content = <FILE>;
    #close(FILE);
    #return @content;
    ##unlink('test.htm');
}

sub get_transactions
{
    if (!$logged_in)
    {
        login();
    }
    my @transactions;
    my $i = 0;
    my @content = get_account_content();
    my @sub_transactions = parse_content(@content);
    @transactions = (@transactions, @sub_transactions);
    while ($i < $DEPTH && $mech->follow_link(class => 'trans-next orangered') != undef)
    {
        @content = split(/\n/, $mech->content());
        @sub_transactions = parse_content(@content);
        @transactions = (@transactions, @sub_transactions);
        $i++;
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

sub get_balance
{
    if (!$logged_in)
    {
        login();
    }
    my @content = get_account_content();
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
    return $balance;
}

sub get_fund_value
{
    if (!$logged_in)
    {
        login();
    }
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

1;
