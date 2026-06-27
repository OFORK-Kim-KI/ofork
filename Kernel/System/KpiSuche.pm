# --
# Kernel/System/KpiSuche.pm - KPI database search functions
# Copyright (C) 2010-2026 OFORK, https://o-fork.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::KpiSuche;

use strict;
use warnings;

use base qw(Kernel::System::EventHandler);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::DB',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::SysConfig',
    'Kernel::System::Time',
    'Kernel::System::Valid',
);

=head1 NAME

Kernel::System::KpiSuche - direkte KPI-Suchen fuer OFORK

=head1 SYNOPSIS

    my $KpiSucheObject = $Kernel::OM->Get('Kernel::System::KpiSuche');

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item TicketCountByStateType()

Zaehlt Tickets anhand des aktuellen StateTypes.

    my $Count = $KpiSucheObject->TicketCountByStateType(
        StateTypes => ['open', 'new'],
        Start      => '2026-01-01 00:00:00', # optional, t.create_time
        End        => '2026-12-31 23:59:59', # optional, t.create_time
        UserID     => 1,
    );

=cut

sub TicketCountByStateType {
    my ( $Self, %Param ) = @_;

    if ( ref $Param{StateTypes} ne 'ARRAY' || !@{ $Param{StateTypes} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need StateTypes!',
        );
        return;
    }

    return $Self->TicketCount(
        %Param,
        StateTypes => $Param{StateTypes},
        DateColumn => 'create_time',
    );
}

=item TicketCountByStateID()

Zaehlt Tickets anhand der aktuellen StateID.

    my $Count = $KpiSucheObject->TicketCountByStateID(
        StateID => 1,
        UserID  => 1,
    );

=cut

sub TicketCountByStateID {
    my ( $Self, %Param ) = @_;

    if ( !$Param{StateID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need StateID!',
        );
        return;
    }

    return $Self->TicketCount(
        %Param,
        StateIDs   => [ $Param{StateID} ],
        DateColumn => 'create_time',
    );
}

=item TicketCountOpenByQueueID()

Zaehlt aktuell offene/neue Tickets einer Queue.

    my $Count = $KpiSucheObject->TicketCountOpenByQueueID(
        QueueID => 1,
        UserID  => 1,
    );

=cut

sub TicketCountOpenByQueueID {
    my ( $Self, %Param ) = @_;

    if ( !$Param{QueueID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need QueueID!',
        );
        return;
    }

    return $Self->TicketCount(
        %Param,
        QueueIDs   => [ $Param{QueueID} ],
        StateTypes => ['open', 'new'],
        DateColumn => 'create_time',
    );
}

=item TicketCount()

Universelle schnelle Ticket-Zaehlung direkt aus der Datenbank.

Moegliche Filter:
    StateTypes => ['open', 'new', 'closed']
    StateIDs   => [1, 4]
    QueueIDs   => [1, 2]
    Start      => '2026-01-01 00:00:00'
    End        => '2026-12-31 23:59:59'
    DateColumn => 'create_time' oder 'change_time'
    UserID     => 1

=cut

sub TicketCount {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my $DateColumn = $Self->_DateColumn( Column => $Param{DateColumn} || 'create_time' );

    my @Where = ('1 = 1');
    my @Bind;

    if ( ref $Param{StateTypes} eq 'ARRAY' && @{ $Param{StateTypes} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 'tst.name',
            Values => $Param{StateTypes},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    if ( ref $Param{StateIDs} eq 'ARRAY' && @{ $Param{StateIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.ticket_state_id',
            Values => $Param{StateIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    if ( ref $Param{QueueIDs} eq 'ARRAY' && @{ $Param{QueueIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.queue_id',
            Values => $Param{QueueIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    if ( $Param{Start} ) {
        my $Start = $Param{Start};
        push @Where, "$DateColumn >= ?";
        push @Bind,  \$Start;
    }

    if ( $Param{End} ) {
        my $End = $Param{End};
        push @Where, "$DateColumn <= ?";
        push @Bind,  \$End;
    }

    my $WhereSQL = join ' AND ', @Where;

    my $SQL = qq~
        SELECT COUNT(DISTINCT t.id)
        FROM ticket t
        INNER JOIN ticket_state ts
            ON ts.id = t.ticket_state_id
        INNER JOIN ticket_state_type tst
            ON tst.id = ts.type_id
        WHERE $WhereSQL
    ~;

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my $Count = 0;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Count = $Row[0] || 0;
    }

    return $Count;
}

=item StateCounts()

Liefert Ticket-Anzahlen pro aktueller StateID.

    my %Data = $KpiSucheObject->StateCounts(
        StateIDs => [1, 4], # optional
        UserID   => 1,
    );

Rueckgabe:
    %Data = (
        Counts => {
            1 => 10,
            4 => 25,
        },
    );

=cut

sub StateCounts {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my @Where = ('1 = 1');
    my @Bind;

    if ( ref $Param{StateIDs} eq 'ARRAY' && @{ $Param{StateIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.ticket_state_id',
            Values => $Param{StateIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    if ( $Param{Start} ) {
        my $Start = $Param{Start};
        push @Where, 't.create_time >= ?';
        push @Bind,  \$Start;
    }

    if ( $Param{End} ) {
        my $End = $Param{End};
        push @Where, 't.create_time <= ?';
        push @Bind,  \$End;
    }

    my $WhereSQL = join ' AND ', @Where;

    my $SQL = qq~
        SELECT
            t.ticket_state_id,
            COUNT(*) AS ticket_count
        FROM ticket t
        WHERE $WhereSQL
        GROUP BY t.ticket_state_id
    ~;

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Counts;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my ( $StateID, $Count ) = @Row;
        next if !$StateID;
        $Counts{$StateID} = $Count || 0;
    }

    my %Result = (
        Counts => \%Counts,
    );

    return %Result;
}

=item QueueOpenCounts()

Liefert offene/neue Ticket-Anzahlen pro QueueID.

    my %Data = $KpiSucheObject->QueueOpenCounts(
        QueueIDs => [1, 2], # optional
        UserID   => 1,
    );

Rueckgabe:
    %Data = (
        Counts => {
            1 => 10,
            2 => 25,
        },
    );

=cut

sub QueueOpenCounts {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my @Where = (
        "tst.name IN ('open', 'new')",
    );
    my @Bind;

    if ( ref $Param{QueueIDs} eq 'ARRAY' && @{ $Param{QueueIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.queue_id',
            Values => $Param{QueueIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    if ( $Param{Start} ) {
        my $Start = $Param{Start};
        push @Where, 't.create_time >= ?';
        push @Bind,  \$Start;
    }

    if ( $Param{End} ) {
        my $End = $Param{End};
        push @Where, 't.create_time <= ?';
        push @Bind,  \$End;
    }

    my $WhereSQL = join ' AND ', @Where;

    my $SQL = qq~
        SELECT
            t.queue_id,
            COUNT(*) AS ticket_count
        FROM ticket t
        INNER JOIN ticket_state ts
            ON ts.id = t.ticket_state_id
        INNER JOIN ticket_state_type tst
            ON tst.id = ts.type_id
        WHERE $WhereSQL
        GROUP BY t.queue_id
    ~;

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Counts;
    while ( my @Row = $DBObject->FetchrowArray() ) {
        my ( $QueueID, $Count ) = @Row;
        next if !$QueueID;
        $Counts{$QueueID} = $Count || 0;
    }

    my %Result = (
        Counts => \%Counts,
    );

    return %Result;
}

=item CloseTimeDistribution()

Liefert die Schliesszeit-Verteilung fuer aktuell geschlossene Tickets.

    my %Data = $KpiSucheObject->CloseTimeDistribution(
        Start  => '2026-01-01 00:00:00',
        End    => '2026-12-31 23:59:59',
        UserID => 1,
    );

Rueckgabe:
    %Data = (
        Buckets => {
            CloseTime8H  => 1,
            CloseTime1T  => 2,
            CloseTime3T  => 3,
            CloseTime5T  => 4,
            CloseTime10T => 5,
            CloseTime30T => 6,
            CloseTime88  => 7,
        },
    );

=cut

sub CloseTimeDistribution {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(Start End UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my @Where = (
        't.change_time >= ?',
        't.change_time <= ?',
        'tst.name = ?',
    );

    my $Start           = $Param{Start};
    my $End             = $Param{End};
    my $StateTypeClosed = 'closed';

    my @Bind = (
        \$Start,
        \$End,
        \$StateTypeClosed,
    );

    if ( ref $Param{QueueIDs} eq 'ARRAY' && @{ $Param{QueueIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.queue_id',
            Values => $Param{QueueIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    my $WhereSQL = join ' AND ', @Where;

    my $SQL = qq~
        SELECT
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 1
                      AND TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) <= 28800
                     THEN 1 ELSE 0 END) AS close_8h,
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 28801
                      AND TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) <= 86400
                     THEN 1 ELSE 0 END) AS close_1t,
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 86401
                      AND TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) <= 259200
                     THEN 1 ELSE 0 END) AS close_3t,
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 259201
                      AND TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) <= 432000
                     THEN 1 ELSE 0 END) AS close_5t,
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 432001
                      AND TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) <= 864000
                     THEN 1 ELSE 0 END) AS close_10t,
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 864001
                      AND TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) <= 2592000
                     THEN 1 ELSE 0 END) AS close_30t,
            SUM(CASE WHEN TIMESTAMPDIFF(SECOND, t.create_time, t.change_time) >= 2592001
                     THEN 1 ELSE 0 END) AS close_88
        FROM ticket t
        INNER JOIN ticket_state ts
            ON ts.id = t.ticket_state_id
        INNER JOIN ticket_state_type tst
            ON tst.id = ts.type_id
        WHERE $WhereSQL
    ~;

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Buckets = (
        CloseTime8H  => 0,
        CloseTime1T  => 0,
        CloseTime3T  => 0,
        CloseTime5T  => 0,
        CloseTime10T => 0,
        CloseTime30T => 0,
        CloseTime88  => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Buckets{CloseTime8H}  = $Row[0] || 0;
        $Buckets{CloseTime1T}  = $Row[1] || 0;
        $Buckets{CloseTime3T}  = $Row[2] || 0;
        $Buckets{CloseTime5T}  = $Row[3] || 0;
        $Buckets{CloseTime10T} = $Row[4] || 0;
        $Buckets{CloseTime30T} = $Row[5] || 0;
        $Buckets{CloseTime88}  = $Row[6] || 0;
    }

    my %Result = (
        Buckets => \%Buckets,
    );

    return %Result;
}

=item AnswerTimeDistribution()

Liefert die Antwortzeit-Verteilung fuer aktuell offene/neue Tickets.

    my %Data = $KpiSucheObject->AnswerTimeDistribution(
        UserID => 1,
    );

=cut

sub AnswerTimeDistribution {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need UserID!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my @Where = (
        "tst.name IN ('open', 'new')",
        'tht.name = ?',
    );

    my $HistoryTypeSendAnswer = 'SendAnswer';

    my @Bind = (
        \$HistoryTypeSendAnswer,
    );

    if ( ref $Param{QueueIDs} eq 'ARRAY' && @{ $Param{QueueIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.queue_id',
            Values => $Param{QueueIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    if ( $Param{Start} ) {
        my $Start = $Param{Start};
        push @Where, 't.create_time >= ?';
        push @Bind,  \$Start;
    }

    if ( $Param{End} ) {
        my $End = $Param{End};
        push @Where, 't.create_time <= ?';
        push @Bind,  \$End;
    }

    my $WhereSQL = join ' AND ', @Where;

    my $SQL = qq~
        SELECT
            SUM(CASE WHEN x.diff_seconds >= 1
                      AND x.diff_seconds <= 7200
                     THEN 1 ELSE 0 END) AS answer_2h,
            SUM(CASE WHEN x.diff_seconds >= 7201
                      AND x.diff_seconds <= 28800
                     THEN 1 ELSE 0 END) AS answer_8h,
            SUM(CASE WHEN x.diff_seconds >= 28801
                      AND x.diff_seconds <= 86400
                     THEN 1 ELSE 0 END) AS answer_1t,
            SUM(CASE WHEN x.diff_seconds >= 86401
                      AND x.diff_seconds <= 259200
                     THEN 1 ELSE 0 END) AS answer_3t,
            SUM(CASE WHEN x.diff_seconds >= 259201
                      AND x.diff_seconds <= 432000
                     THEN 1 ELSE 0 END) AS answer_5t,
            SUM(CASE WHEN x.diff_seconds >= 432001
                      AND x.diff_seconds <= 864000
                     THEN 1 ELSE 0 END) AS answer_10t,
            SUM(CASE WHEN x.diff_seconds >= 864001
                      AND x.diff_seconds <= 2592000
                     THEN 1 ELSE 0 END) AS answer_30t,
            SUM(CASE WHEN x.diff_seconds >= 2592001
                     THEN 1 ELSE 0 END) AS answer_88
        FROM (
            SELECT
                TIMESTAMPDIFF(SECOND, t.create_time, th.create_time) AS diff_seconds
            FROM ticket t
            INNER JOIN ticket_state ts
                ON ts.id = t.ticket_state_id
            INNER JOIN ticket_state_type tst
                ON tst.id = ts.type_id
            INNER JOIN ticket_history th
                ON th.ticket_id = t.id
            INNER JOIN ticket_history_type tht
                ON tht.id = th.history_type_id
            WHERE $WhereSQL
        ) x
    ~;

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    my %Buckets = (
        AnswerTime2H  => 0,
        AnswerTime8H  => 0,
        AnswerTime1T  => 0,
        AnswerTime3T  => 0,
        AnswerTime5T  => 0,
        AnswerTime10T => 0,
        AnswerTime30T => 0,
        AnswerTime88  => 0,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        $Buckets{AnswerTime2H}  = $Row[0] || 0;
        $Buckets{AnswerTime8H}  = $Row[1] || 0;
        $Buckets{AnswerTime1T}  = $Row[2] || 0;
        $Buckets{AnswerTime3T}  = $Row[3] || 0;
        $Buckets{AnswerTime5T}  = $Row[4] || 0;
        $Buckets{AnswerTime10T} = $Row[5] || 0;
        $Buckets{AnswerTime30T} = $Row[6] || 0;
        $Buckets{AnswerTime88}  = $Row[7] || 0;
    }

    my %Result = (
        Buckets => \%Buckets,
    );

    return %Result;
}

=item CreatedTicketsByMonth()

Liefert erstellte Tickets pro Monat.

    my %Data = $KpiSucheObject->CreatedTicketsByMonth(
        Start  => '2026-01-01 00:00:00',
        End    => '2026-12-31 23:59:59',
        UserID => 1,
    );

Rueckgabe:
    %Data = (
        Months => {
            '01' => 10,
            '02' => 15,
        },
    );

=cut

sub CreatedTicketsByMonth {
    my ( $Self, %Param ) = @_;

    return $Self->_TicketsByMonth(
        %Param,
        Mode => 'Created',
    );
}

=item ClosedTicketsByMonth()

Liefert geschlossene Tickets pro Monat.

    my %Data = $KpiSucheObject->ClosedTicketsByMonth(
        Start  => '2026-01-01 00:00:00',
        End    => '2026-12-31 23:59:59',
        UserID => 1,
    );

Rueckgabe:
    %Data = (
        Months => {
            '01' => 10,
            '02' => 15,
        },
    );

=cut

sub ClosedTicketsByMonth {
    my ( $Self, %Param ) = @_;

    return $Self->_TicketsByMonth(
        %Param,
        Mode => 'Closed',
    );
}

=item CreatedClosedTicketsByMonth()

Liefert erstellte und geschlossene Tickets pro Monat in einem Methodenaufruf.

    my %Data = $KpiSucheObject->CreatedClosedTicketsByMonth(
        Start  => '2026-01-01 00:00:00',
        End    => '2026-12-31 23:59:59',
        UserID => 1,
    );

Rueckgabe:
    %Data = (
        Created => { '01' => 10 },
        Closed  => { '01' => 8  },
    );

=cut

sub CreatedClosedTicketsByMonth {
    my ( $Self, %Param ) = @_;

    my %Created = $Self->CreatedTicketsByMonth(%Param);
    my %Closed  = $Self->ClosedTicketsByMonth(%Param);

    my %Result = (
        Created => $Created{Months} || {},
        Closed  => $Closed{Months}  || {},
    );

    return %Result;
}

sub _TicketsByMonth {
    my ( $Self, %Param ) = @_;

    for my $Needed (qw(Start End UserID Mode)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }

    my %AllowedMode = (
        Created => 1,
        Closed  => 1,
    );

    if ( !$AllowedMode{ $Param{Mode} } ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Invalid Mode!',
        );
        return;
    }

    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my %Months = (
        '01' => 0,
        '02' => 0,
        '03' => 0,
        '04' => 0,
        '05' => 0,
        '06' => 0,
        '07' => 0,
        '08' => 0,
        '09' => 0,
        '10' => 0,
        '11' => 0,
        '12' => 0,
    );

    my @Where;
    my @Bind;
    my $DateColumn;

    if ( $Param{Mode} eq 'Created' ) {
        $DateColumn = 't.create_time';
    }
    else {
        $DateColumn = 't.change_time';
        push @Where, 'tst.name = ?';
        my $StateTypeClosed = 'closed';
        push @Bind, \$StateTypeClosed;
    }

    my $Start = $Param{Start};
    my $End   = $Param{End};

    push @Where, "$DateColumn >= ?";
    push @Where, "$DateColumn <= ?";
    push @Bind,  \$Start;
    push @Bind,  \$End;

    if ( ref $Param{QueueIDs} eq 'ARRAY' && @{ $Param{QueueIDs} } ) {
        my ( $SQLPart, @SQLBind ) = $Self->_InSQL(
            Field  => 't.queue_id',
            Values => $Param{QueueIDs},
        );
        push @Where, $SQLPart;
        push @Bind,  @SQLBind;
    }

    my $WhereSQL = join ' AND ', @Where;

    my $SQL = qq~
        SELECT
            DATE_FORMAT($DateColumn, '%m') AS stat_month,
            COUNT(*) AS stat_count
        FROM ticket t
        INNER JOIN ticket_state ts
            ON ts.id = t.ticket_state_id
        INNER JOIN ticket_state_type tst
            ON tst.id = ts.type_id
        WHERE $WhereSQL
        GROUP BY DATE_FORMAT($DateColumn, '%m')
        ORDER BY stat_month
    ~;

    $DBObject->Prepare(
        SQL  => $SQL,
        Bind => \@Bind,
    );

    while ( my @Row = $DBObject->FetchrowArray() ) {
        my ( $Month, $Count ) = @Row;
        next if !$Month;
        $Months{$Month} = $Count || 0;
    }

    my %Result = (
        Months => \%Months,
    );

    return %Result;
}

sub _InSQL {
    my ( $Self, %Param ) = @_;

    if ( !$Param{Field} ) {
        return;
    }

    if ( ref $Param{Values} ne 'ARRAY' || !@{ $Param{Values} } ) {
        return;
    }

    my @Placeholders;
    my @Bind;

    for my $Value ( @{ $Param{Values} } ) {
        push @Placeholders, '?';

        my $Copy = $Value;
        push @Bind, \$Copy;
    }

    my $SQL = $Param{Field} . ' IN (' . join( ', ', @Placeholders ) . ')';

    return ( $SQL, @Bind );
}

sub _DateColumn {
    my ( $Self, %Param ) = @_;

    my %Map = (
        create_time     => 't.create_time',
        change_time     => 't.change_time',
        't.create_time' => 't.create_time',
        't.change_time' => 't.change_time',
    );

    return $Map{ $Param{Column} || '' } || 't.create_time';
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OFORK project (L<https://o-fork.de/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
this file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
