# --
# Kernel/Modules/AgentKPI.pm
# Copyright (C) 2010-2025 OFORK, https://o-fork.de
# --
# $Id: AgentKPI.pm,v 1.1.1.1 2018/07/16 14:49:06 ud Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentKPI;

use strict;
use warnings;

use Kernel::Language qw(Translatable);
use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get form id
    $Self->{FormID}
        = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'FormID' );

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $ConfigObject    = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject    = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ParamObject     = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $UserObject      = $Kernel::OM->Get('Kernel::System::User');
    my $GroupObject     = $Kernel::OM->Get('Kernel::System::Group');
    my $KpiSucheObject  = $Kernel::OM->Get('Kernel::System::KpiSuche');
    my $StateObject     = $Kernel::OM->Get('Kernel::System::State');
    my $QueueObject     = $Kernel::OM->Get('Kernel::System::Queue');
    my $TimeObject      = $Kernel::OM->Get('Kernel::System::Time');
    my $DateTimeObject  = $Kernel::OM->Create(
        'Kernel::System::DateTime'
    );

    # get params
    my %GetParam;

    for my $Key (
        qw(FromDateDay FromDateMonth FromDateYear ToDateDay ToDateMonth ToDateYear FromDateErstYear OhneDatum)
        )
    {
        $GetParam{$Key} = $ParamObject->GetParam( Param => $Key );
    }

    if ( $GetParam{OhneDatum} ) {
        $GetParam{FromDateDay} = '';
        $GetParam{FromDateMonth} = '';
        $GetParam{FromDateYear} = '';
        $GetParam{ToDateDay} = '';
        $GetParam{ToDateMonth} = '';
        $GetParam{ToDateYear} = '';
    }

    my @StateIDs = $ParamObject->GetArray( Param => 'StateID' );
    my @QueueIDs = $ParamObject->GetArray( Param => 'QueueID' );

    $Param{FormID} = $Self->{FormID};

    my ( $StartSec, $StartMin, $StartHour, $StartDay, $StartMonth, $StartYear, $StartWeekDay )
        = $TimeObject->SystemTime2Date(
        SystemTime => $TimeObject->SystemTime(),
        );
    my $LastDayOfMonth = $DateTimeObject->LastDayOfMonthGet();

    $Param{FromDateString} = $LayoutObject->BuildDateSelection(
        Prefix               => 'FromDate',
        FromDateYear         => $StartYear,
        FromDateMonth        => $StartMonth,
        FromDateDay          => 01,
        FromDateHour         => 00,
        FromDateMinute       => 01,
        Format               => 'DateInputFormat',
        YearPeriodPast       => 20,
        YearPeriodFuture     => 1,
        DiffTime             => 0,
        Class                => $Param{Errors}->{FromDateInvalid},
        Validate             => 1,
        ValidateDateInFuture => 0,
    );

    $Param{ToDateString} = $LayoutObject->BuildDateSelection(
        Prefix               => 'ToDate',
        ToDateYear           => $StartYear,
        ToDateMonth          => $StartMonth,
        ToDateDay            => $LastDayOfMonth->{Day},
        ToDateHour           => 23,
        ToDateMinute         => 59,
        Format               => 'DateInputFormat',
        YearPeriodPast       => 20,
        YearPeriodFuture     => 1,
        DiffTime             => 3600,
        Class                => $Param{Errors}->{ToDateInvalid},
        Validate             => 1,
        ValidateDateInFuture => 0,
    );

    $Param{FromDateErstString} = $LayoutObject->BuildDateSelection(
        Prefix               => 'FromDateErst',
        FromDateErstYear     => $StartYear,
        FromDateErstMonth    => 01,
        FromDateErstDay      => 01,
        Format               => 'DateInputFormat',
        YearPeriodPast       => 20,
        YearPeriodFuture     => 0,
        Validate             => 1,
        ValidateDateInFuture => 0,
    );

    my $FilterStart = '';
    my $FilterEnd   = '';

    if ( $GetParam{FromDateYear} ) {
        $FilterStart = "$GetParam{FromDateYear}-$GetParam{FromDateMonth}-$GetParam{FromDateDay} 00:00:00";
        $FilterEnd   = "$GetParam{ToDateYear}-$GetParam{ToDateMonth}-$GetParam{ToDateDay} 00:00:00";
    }

    my $openTickets  = '';
    my $closeTickets = '';

    if ($FilterStart) {
        $openTickets = $KpiSucheObject->TicketCountByStateType(
            StateTypes => ['open','new'],
            Start      => $FilterStart,
            End        => $FilterEnd,
            UserID     => 1,
        );
    }
    else {
        $openTickets = $KpiSucheObject->TicketCountByStateType(
            StateTypes => ['open','new'],
            UserID     => 1,
        );
    }

    if ($FilterStart) {
        $closeTickets = $KpiSucheObject->TicketCountByStateType(
            StateTypes => ['closed'],
            Start      => $FilterStart,
            End        => $FilterEnd,
            UserID     => 1,
        );
    }
    else {
        $closeTickets = $KpiSucheObject->TicketCountByStateType(
            StateTypes => ['closed'],
            UserID     => 1,
        );
    }

    $Param{'openTickets'}  = $openTickets  || 0;
    $Param{'closeTickets'} = $closeTickets || 0;

    my %StateList = $StateObject->StateList(
        UserID => 1,
        Valid  => 1,
    );

    $Param{StateStrg} = $LayoutObject->BuildSelection(
        Data         => \%StateList,
        Name         => 'StateID',
        Multiple     => 1,
        Size         => 10,
        PossibleNone => 0,
        Sort         => 'AlphanumericKey',
        SelectedIDs   => @StateIDs,
        Translation  => 1,
        Class        => "Modernize",
    );

    my %StateCountData;
    if (@StateIDs) {
        %StateCountData = $KpiSucheObject->StateCounts(
            StateIDs => \@StateIDs,
            UserID   => 1,
        );
    }
    else {
        %StateCountData = $KpiSucheObject->StateCounts(
            UserID => 1,
        );
    }

    my $openTicketState = 0;
    if ( @StateIDs ) {

        for my $StateID ( @StateIDs ) {

            $openTicketState = $StateCountData{Counts}->{$StateID} || 0;

            my $State = $StateObject->StateLookup(
                StateID => $StateID,
            );

            if ( $openTicketState >= 1 ) {
                $State = $LayoutObject->{LanguageObject}->Translate($State);
                $Param{'States'} .= '{y: ' . $openTicketState . ', label: "' . $State . '", name: "' . $State . '"},';
            }
            $openTicketState = 0;
        }
    }
    else {

        for my $StateID ( sort keys %StateList ) {

            $openTicketState = $StateCountData{Counts}->{$StateID} || 0;
            if ( $openTicketState >= 1 ) {
                $StateList{$StateID} = $LayoutObject->{LanguageObject}->Translate($StateList{$StateID});
                $Param{'States'} .= '{y: ' . $openTicketState . ', label: "' . $StateList{$StateID} . '", name: "' . $StateList{$StateID} . '"},';
            }
            $openTicketState = 0;
        }
    }

    my %Queues = $QueueObject->QueueList( Valid => 1 );

    $Param{QueueStrg} = $LayoutObject->BuildSelection(
        Data         => \%Queues,
        Name         => 'QueueID',
        Multiple     => 1,
        Size         => 10,
        PossibleNone => 0,
        Sort         => 'AlphanumericKey',
        SelectedIDs   => @QueueIDs,
        Translation  => 1,
        Class        => "Modernize",
    );

    my %QueueCountData;
    if (@QueueIDs) {
        %QueueCountData = $KpiSucheObject->QueueOpenCounts(
            QueueIDs => \@QueueIDs,
            UserID   => 1,
        );
    }
    else {
        %QueueCountData = $KpiSucheObject->QueueOpenCounts(
            UserID => 1,
        );
    }

    my $openTicketQueue = 0;
    if ( @QueueIDs ) {

        for my $QueueID ( @QueueIDs ) {

            $openTicketQueue = $QueueCountData{Counts}->{$QueueID} || 0;

            my $Queue = $QueueObject->QueueLookup( QueueID => $QueueID );

            if ( $openTicketQueue >= 1 ) {
                $Queue = $LayoutObject->{LanguageObject}->Translate($Queue);
                $Param{'Queues'} .= '{y: ' . $openTicketQueue . ', label: "' . $Queue . '", name: "' . $Queue . '"},';
            }
            $openTicketQueue = 0;
        }
    }
    else {

        for my $QueueID ( sort keys %Queues ) {

            $openTicketQueue = $QueueCountData{Counts}->{$QueueID} || 0;

            if ( $openTicketQueue >= 1 ) {
                $Queues{$QueueID} = $LayoutObject->{LanguageObject}->Translate($Queues{$QueueID});
                $Param{'Queues'} .= '{y: ' . $openTicketQueue . ', label: "' . $Queues{$QueueID} . '", name: "' . $Queues{$QueueID} . '"},';
            }
            $openTicketQueue = 0;
        }
    }

    my $StartDate = "";
    my $EndDate   = "";
    if ( !$Param{StartMonth} ) {
        my ($Sec, $Min, $Hour, $Day, $Month, $Year, $WeekDay) = $TimeObject->SystemTime2Date(
            SystemTime => $TimeObject->SystemTime(),
        );
        $StartDate = "$Year-01-01 00:00:00";
    }
    else {
        $StartDate = "$Param{StartYear}-$Param{StartMonth}-$Param{StartDay} 00:00:00";
    }

    if ( !$Param{EndMonth} ) {
        $EndDate = $TimeObject->CurrentTimestamp();
    }
    else {
        $EndDate = "$Param{EndYear}-$Param{EndMonth}-$Param{EndDay} 23:59:59";
    }

    my %CloseTimeData = $KpiSucheObject->CloseTimeDistribution(
        Start  => $StartDate,
        End    => $EndDate,
        UserID => 1,
    );

    my $CloseTime8H  = $CloseTimeData{Buckets}->{CloseTime8H}  || 0;
    my $CloseTime1T  = $CloseTimeData{Buckets}->{CloseTime1T}  || 0;
    my $CloseTime3T  = $CloseTimeData{Buckets}->{CloseTime3T}  || 0;
    my $CloseTime5T  = $CloseTimeData{Buckets}->{CloseTime5T}  || 0;
    my $CloseTime10T = $CloseTimeData{Buckets}->{CloseTime10T} || 0;
    my $CloseTime30T = $CloseTimeData{Buckets}->{CloseTime30T} || 0;
    my $CloseTime88  = $CloseTimeData{Buckets}->{CloseTime88}  || 0;

    $Param{'CloseTime'} .= '{y: ' . $CloseTime8H . ', label: "< 8 Stunden"},';
    $Param{'CloseTime'} .= '{y: ' . $CloseTime1T . ', label: "< 24 Stunden"},';
    $Param{'CloseTime'} .= '{y: ' . $CloseTime3T . ', label: "< 3 Tage"},';
    $Param{'CloseTime'} .= '{y: ' . $CloseTime5T . ', label: "< 5 Tage"},';
    $Param{'CloseTime'} .= '{y: ' . $CloseTime10T . ', label: "< 10 Tage"},';
    $Param{'CloseTime'} .= '{y: ' . $CloseTime30T . ', label: "< 30 Tage"},';
    $Param{'CloseTime'} .= '{y: ' . $CloseTime88 . ', label: "> 30 Tage"},';

    my %AnswerTimeData = $KpiSucheObject->AnswerTimeDistribution(
        UserID => 1,
    );

    my $AnswerTime2H  = $AnswerTimeData{Buckets}->{AnswerTime2H}  || 0;
    my $AnswerTime8H  = $AnswerTimeData{Buckets}->{AnswerTime8H}  || 0;
    my $AnswerTime1T  = $AnswerTimeData{Buckets}->{AnswerTime1T}  || 0;
    my $AnswerTime3T  = $AnswerTimeData{Buckets}->{AnswerTime3T}  || 0;
    my $AnswerTime5T  = $AnswerTimeData{Buckets}->{AnswerTime5T}  || 0;
    my $AnswerTime10T = $AnswerTimeData{Buckets}->{AnswerTime10T} || 0;
    my $AnswerTime30T = $AnswerTimeData{Buckets}->{AnswerTime30T} || 0;
    my $AnswerTime88  = $AnswerTimeData{Buckets}->{AnswerTime88}  || 0;

    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime2H . ', label: "< 2 Stunden"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime8H . ', label: "< 8 Stunden"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime1T . ', label: "< 24 Stunden"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime3T . ', label: "< 3 Tage"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime5T . ', label: "< 5 Tage"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime10T . ', label: "< 10 Tage"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime30T . ', label: "< 30 Tage"},';
    $Param{'AnswerTime'} .= '{y: ' . $AnswerTime88 . ', label: "> 30 Tage"},';

    my $StartYearSearch = '';
    my $EndYearSearch   = '';

    if ( $GetParam{FromDateErstYear} ) {
        $StartYearSearch = "$GetParam{FromDateErstYear}-01-01 00:00:00";
        $EndYearSearch   = "$GetParam{FromDateErstYear}-12-31 00:00:00";
    }
    else {
        $StartYearSearch = "$StartYear-01-01 00:00:00";
        $EndYearSearch   = "$StartYear-12-31 00:00:00";
    }

    my %CreatedClosedData = $KpiSucheObject->CreatedClosedTicketsByMonth(
        Start  => $StartYearSearch,
        End    => $EndYearSearch,
        UserID => 1,
    );

    my $openTicketsJan  = $CreatedClosedData{Created}->{'01'} || 0;
    my $openTicketsFeb  = $CreatedClosedData{Created}->{'02'} || 0;
    my $openTicketsMar  = $CreatedClosedData{Created}->{'03'} || 0;
    my $openTicketsApr  = $CreatedClosedData{Created}->{'04'} || 0;
    my $openTicketsMai  = $CreatedClosedData{Created}->{'05'} || 0;
    my $openTicketsJun  = $CreatedClosedData{Created}->{'06'} || 0;
    my $openTicketsJul  = $CreatedClosedData{Created}->{'07'} || 0;
    my $openTicketsAug  = $CreatedClosedData{Created}->{'08'} || 0;
    my $openTicketsSept = $CreatedClosedData{Created}->{'09'} || 0;
    my $openTicketsOkt  = $CreatedClosedData{Created}->{'10'} || 0;
    my $openTicketsNov  = $CreatedClosedData{Created}->{'11'} || 0;
    my $openTicketsDez  = $CreatedClosedData{Created}->{'12'} || 0;

    $Param{'OpenTicketsYear'} .= '{label: "Jan", y: ' . $openTicketsJan . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Feb", y: ' . $openTicketsFeb . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Mar", y: ' . $openTicketsMar . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Apr", y: ' . $openTicketsApr . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Mai", y: ' . $openTicketsMai . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Jun", y: ' . $openTicketsJun . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Jul", y: ' . $openTicketsJul . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Aug", y: ' . $openTicketsAug . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Sept", y: ' . $openTicketsSept . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Okt", y: ' . $openTicketsOkt . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Nov", y: ' . $openTicketsNov . ',},';
    $Param{'OpenTicketsYear'} .= '{label: "Dez", y: ' . $openTicketsDez . '}';

    my $closeTicketsJan  = $CreatedClosedData{Closed}->{'01'} || 0;
    my $closeTicketsFeb  = $CreatedClosedData{Closed}->{'02'} || 0;
    my $closeTicketsMar  = $CreatedClosedData{Closed}->{'03'} || 0;
    my $closeTicketsApr  = $CreatedClosedData{Closed}->{'04'} || 0;
    my $closeTicketsMai  = $CreatedClosedData{Closed}->{'05'} || 0;
    my $closeTicketsJun  = $CreatedClosedData{Closed}->{'06'} || 0;
    my $closeTicketsJul  = $CreatedClosedData{Closed}->{'07'} || 0;
    my $closeTicketsAug  = $CreatedClosedData{Closed}->{'08'} || 0;
    my $closeTicketsSept = $CreatedClosedData{Closed}->{'09'} || 0;
    my $closeTicketsOkt  = $CreatedClosedData{Closed}->{'10'} || 0;
    my $closeTicketsNov  = $CreatedClosedData{Closed}->{'11'} || 0;
    my $closeTicketsDez  = $CreatedClosedData{Closed}->{'12'} || 0;

    $Param{'CloseTicketsYear'} .= '{label: "Jan", y: ' . $closeTicketsJan . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Feb", y: ' . $closeTicketsFeb . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Mar", y: ' . $closeTicketsMar . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Apr", y: ' . $closeTicketsApr . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Mai", y: ' . $closeTicketsMai . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Jun", y: ' . $closeTicketsJun . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Jul", y: ' . $closeTicketsJul . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Aug", y: ' . $closeTicketsAug . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Sept", y: ' . $closeTicketsSept . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Okt", y: ' . $closeTicketsOkt . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Nov", y: ' . $closeTicketsNov . ',},';
    $Param{'CloseTicketsYear'} .= '{label: "Dez", y: ' . $closeTicketsDez . '}';

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();
    $Output .= $LayoutObject->Output(
        TemplateFile => $Self->{Action},
        Data         => \%Param
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

1;
