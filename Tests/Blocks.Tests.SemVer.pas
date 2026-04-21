{******************************************************************************}
{                                                                              }
{  DelphiBlock Installer                                                       }
{                                                                              }
{  Copyright (c) Luca Minuti <code@lucaminuti.it>                              }
{  All rights reserved.                                                        }
{                                                                              }
{  https://github.com/delphi-blocks/blocks                                     }
{                                                                              }
{  Licensed under the Apache-2.0 license                                       }
{                                                                              }
{******************************************************************************}
unit Blocks.Tests.SemVer;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,

  Blocks.Core;

type
  [TestFixture]
  TSemVerTest = class(TObject)
  private
    function V(const S: string): TSemVer;
  public
    [Test]
    procedure TestTryParse;
    [Test]
    procedure TestCompareTo;
    [Test]
    procedure TestMatchExact;
    [Test]
    procedure TestMatchOperators;
    [Test]
    procedure TestMatchCaret;
    [Test]
    procedure TestMatchTilde;
    [Test]
    procedure TestMatchWildcard;
    [Test]
    procedure TestMatchRange;
    [Test]
    procedure TestBestMatch;
  end;

implementation

{ TSemVerTest }

function TSemVerTest.V(const S: string): TSemVer;
begin
  Result := TSemVer.Parse(S);
end;

procedure TSemVerTest.TestTryParse;
var
  LVer: TSemVer;
begin
  Assert.IsTrue(
    TSemVer.TryParse('1.2.3', LVer) and (LVer.Major = 1) and (LVer.Minor = 2) and (LVer.Patch = 3),
    '1.2.3 parses correctly');

  Assert.IsTrue(
    TSemVer.TryParse('1.2', LVer) and (LVer.Major = 1) and (LVer.Minor = 2) and (LVer.Patch = 0),
    '1.2 sets patch to 0');

  Assert.IsTrue(
    TSemVer.TryParse('1', LVer) and (LVer.Major = 1) and (LVer.Minor = 0) and (LVer.Patch = 0),
    '1 sets minor and patch to 0');

  Assert.IsTrue(
    TSemVer.TryParse('0.0.0', LVer) and (LVer.Major = 0) and (LVer.Minor = 0) and (LVer.Patch = 0),
    '0.0.0 parses correctly');

  Assert.IsFalse(TSemVer.TryParse('abc', LVer), '"abc" returns False');
  Assert.IsFalse(TSemVer.TryParse('', LVer),    '"" returns False');
  Assert.IsFalse(TSemVer.TryParse('1.x.3', LVer), '"1.x.3" returns False');

  Assert.AreEqual('2.5.11', TSemVer.Parse('2.5.11').ToString, 'ToString round-trips');
end;

procedure TSemVerTest.TestCompareTo;
begin
  Assert.AreEqual(0, V('1.2.3').CompareTo(V('1.2.3')), '1.2.3 = 1.2.3');
  Assert.IsTrue(V('1.2.4').CompareTo(V('1.2.3')) > 0, '1.2.4 > 1.2.3');
  Assert.IsTrue(V('1.2.3').CompareTo(V('1.2.4')) < 0, '1.2.3 < 1.2.4');
  Assert.IsTrue(V('1.3.0').CompareTo(V('1.2.9')) > 0, '1.3.0 > 1.2.9');
  Assert.IsTrue(V('2.0.0').CompareTo(V('1.9.9')) > 0, '2.0.0 > 1.9.9');
  Assert.IsTrue(V('1.0.0').CompareTo(V('2.0.0')) < 0, '1.0.0 < 2.0.0');
end;

procedure TSemVerTest.TestMatchExact;
begin
  Assert.IsTrue(V('1.2.3').MatchesConstraint(''),      'empty matches any');
  Assert.IsTrue(V('9.9.9').MatchesConstraint('*'),     '* matches any');
  Assert.IsTrue(V('1.2.3').MatchesConstraint('1.2.3'), '1.2.3 matches 1.2.3');
  Assert.IsFalse(V('1.2.4').MatchesConstraint('1.2.3'), '1.2.4 not matches 1.2.3');
  Assert.IsFalse(V('2.0.0').MatchesConstraint('1.2.3'), '2.0.0 not matches 1.2.3');
end;

procedure TSemVerTest.TestMatchOperators;
begin
  Assert.IsTrue(V('1.2.3').MatchesConstraint('>=1.2.3'),  '>=1.2.3: 1.2.3 matches');
  Assert.IsTrue(V('1.2.4').MatchesConstraint('>=1.2.3'),  '>=1.2.3: 1.2.4 matches');
  Assert.IsTrue(V('2.0.0').MatchesConstraint('>=1.2.3'),  '>=1.2.3: 2.0.0 matches');
  Assert.IsFalse(V('1.2.2').MatchesConstraint('>=1.2.3'), '>=1.2.3: 1.2.2 not matches');

  Assert.IsTrue(V('1.2.4').MatchesConstraint('>1.2.3'),   '>1.2.3: 1.2.4 matches');
  Assert.IsTrue(V('2.0.0').MatchesConstraint('>1.2.3'),   '>1.2.3: 2.0.0 matches');
  Assert.IsFalse(V('1.2.3').MatchesConstraint('>1.2.3'),  '>1.2.3: 1.2.3 not matches');
  Assert.IsFalse(V('1.2.2').MatchesConstraint('>1.2.3'),  '>1.2.3: 1.2.2 not matches');

  Assert.IsTrue(V('1.2.3').MatchesConstraint('<=1.2.3'),  '<=1.2.3: 1.2.3 matches');
  Assert.IsTrue(V('1.2.2').MatchesConstraint('<=1.2.3'),  '<=1.2.3: 1.2.2 matches');
  Assert.IsTrue(V('0.9.0').MatchesConstraint('<=1.2.3'),  '<=1.2.3: 0.9.0 matches');
  Assert.IsFalse(V('1.2.4').MatchesConstraint('<=1.2.3'), '<=1.2.3: 1.2.4 not matches');

  Assert.IsTrue(V('1.9.9').MatchesConstraint('<2.0.0'),   '<2.0.0: 1.9.9 matches');
  Assert.IsTrue(V('0.1.0').MatchesConstraint('<2.0.0'),   '<2.0.0: 0.1.0 matches');
  Assert.IsFalse(V('2.0.0').MatchesConstraint('<2.0.0'),  '<2.0.0: 2.0.0 not matches');
  Assert.IsFalse(V('2.0.1').MatchesConstraint('<2.0.0'),  '<2.0.0: 2.0.1 not matches');
end;

procedure TSemVerTest.TestMatchCaret;
begin
  Assert.IsTrue(V('3.3.0').MatchesConstraint('^3.0.5'),   '^3.0.5: 3.3.0 matches');
  Assert.IsFalse(V('3.3.0').MatchesConstraint('^3.3.1'),  '^3.3.1: 3.3.0 not matches');
  Assert.IsTrue(V('1.2.3').MatchesConstraint('^1.2.3'),   '^1.2.3: 1.2.3 matches');
  Assert.IsTrue(V('1.2.9').MatchesConstraint('^1.2.3'),   '^1.2.3: 1.2.9 matches');
  Assert.IsTrue(V('1.9.0').MatchesConstraint('^1.2.3'),   '^1.2.3: 1.9.0 matches');
  Assert.IsTrue(V('1.99.99').MatchesConstraint('^1.2.3'), '^1.2.3: 1.99.99 matches');
  Assert.IsFalse(V('2.0.0').MatchesConstraint('^1.2.3'),  '^1.2.3: 2.0.0 not matches');
  Assert.IsFalse(V('1.2.2').MatchesConstraint('^1.2.3'),  '^1.2.3: 1.2.2 not matches');
  Assert.IsFalse(V('0.9.9').MatchesConstraint('^1.2.3'),  '^1.2.3: 0.9.9 not matches');
end;

procedure TSemVerTest.TestMatchTilde;
begin
  Assert.IsTrue(V('1.2.3').MatchesConstraint('~1.2.3'),   '~1.2.3: 1.2.3 matches');
  Assert.IsTrue(V('1.2.9').MatchesConstraint('~1.2.3'),   '~1.2.3: 1.2.9 matches');
  Assert.IsFalse(V('1.3.0').MatchesConstraint('~1.2.3'),  '~1.2.3: 1.3.0 not matches');
  Assert.IsFalse(V('2.0.0').MatchesConstraint('~1.2.3'),  '~1.2.3: 2.0.0 not matches');
  Assert.IsFalse(V('1.2.2').MatchesConstraint('~1.2.3'),  '~1.2.3: 1.2.2 not matches');
end;

procedure TSemVerTest.TestMatchWildcard;
begin
  Assert.IsTrue(V('1.2.0').MatchesConstraint('1.2.*'),    '1.2.*: 1.2.0 matches');
  Assert.IsTrue(V('1.2.9').MatchesConstraint('1.2.*'),    '1.2.*: 1.2.9 matches');
  Assert.IsTrue(V('1.2.99').MatchesConstraint('1.2.*'),   '1.2.*: 1.2.99 matches');
  Assert.IsFalse(V('1.3.0').MatchesConstraint('1.2.*'),   '1.2.*: 1.3.0 not matches');
  Assert.IsFalse(V('2.2.0').MatchesConstraint('1.2.*'),   '1.2.*: 2.2.0 not matches');

  Assert.IsTrue(V('1.0.0').MatchesConstraint('1.*'),      '1.*: 1.0.0 matches');
  Assert.IsTrue(V('1.9.9').MatchesConstraint('1.*'),      '1.*: 1.9.9 matches');
  Assert.IsFalse(V('2.0.0').MatchesConstraint('1.*'),     '1.*: 2.0.0 not matches');
  Assert.IsFalse(V('0.9.9').MatchesConstraint('1.*'),     '1.*: 0.9.9 not matches');
end;

procedure TSemVerTest.TestMatchRange;
begin
  Assert.IsTrue(V('1.2.0').MatchesConstraint('>=1.2.0 <2.0.0'),  '>=1.2.0 <2.0.0: 1.2.0 matches');
  Assert.IsTrue(V('1.5.0').MatchesConstraint('>=1.2.0 <2.0.0'),  '>=1.2.0 <2.0.0: 1.5.0 matches');
  Assert.IsTrue(V('1.9.9').MatchesConstraint('>=1.2.0 <2.0.0'),  '>=1.2.0 <2.0.0: 1.9.9 matches');
  Assert.IsFalse(V('2.0.0').MatchesConstraint('>=1.2.0 <2.0.0'), '>=1.2.0 <2.0.0: 2.0.0 not matches');
  Assert.IsFalse(V('1.1.9').MatchesConstraint('>=1.2.0 <2.0.0'), '>=1.2.0 <2.0.0: 1.1.9 not matches');
  Assert.IsFalse(V('0.9.0').MatchesConstraint('>=1.2.0 <2.0.0'), '>=1.2.0 <2.0.0: 0.9.0 not matches');

  Assert.IsTrue(V('1.0.1').MatchesConstraint('>1.0.0 <=1.5.0'),  '>1.0.0 <=1.5.0: 1.0.1 matches');
  Assert.IsTrue(V('1.5.0').MatchesConstraint('>1.0.0 <=1.5.0'),  '>1.0.0 <=1.5.0: 1.5.0 matches');
  Assert.IsFalse(V('1.0.0').MatchesConstraint('>1.0.0 <=1.5.0'), '>1.0.0 <=1.5.0: 1.0.0 not matches');
  Assert.IsFalse(V('1.5.1').MatchesConstraint('>1.0.0 <=1.5.0'), '>1.0.0 <=1.5.0: 1.5.1 not matches');
end;

procedure TSemVerTest.TestBestMatch;
var
  LBest: TSemVer;
  LVersions: TArray<TSemVer>;
begin
  LVersions := [
    TSemVer.Parse('1.0.0'),
    TSemVer.Parse('1.2.3'),
    TSemVer.Parse('1.5.0'),
    TSemVer.Parse('2.0.0'),
    TSemVer.Parse('2.1.0')
  ];

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '', LBest) and (LBest.ToString = '2.1.0'),
    'empty constraint picks highest');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '*', LBest) and (LBest.ToString = '2.1.0'),
    '* picks highest');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '^1.0.0', LBest) and (LBest.ToString = '1.5.0'),
    '^1.0.0 picks highest 1.x');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '~1.2.3', LBest) and (LBest.ToString = '1.2.3'),
    '~1.2.3 picks highest 1.2.x');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '>=1.2.3', LBest) and (LBest.ToString = '2.1.0'),
    '>=1.2.3 picks 2.1.0');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '<2.0.0', LBest) and (LBest.ToString = '1.5.0'),
    '<2.0.0 picks 1.5.0');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '1.2.*', LBest) and (LBest.ToString = '1.2.3'),
    '1.2.* picks 1.2.3');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '1.*', LBest) and (LBest.ToString = '1.5.0'),
    '1.* picks 1.5.0');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '2.0.0', LBest) and (LBest.ToString = '2.0.0'),
    'exact 2.0.0 matches');

  Assert.IsTrue(
    TSemVer.BestMatch(LVersions, '>=1.2.3 <2.0.0', LBest) and (LBest.ToString = '1.5.0'),
    '>=1.2.3 <2.0.0 picks 1.5.0');

  Assert.IsFalse(TSemVer.BestMatch(LVersions, '>9.0.0', LBest), '>9.0.0 returns False');
  Assert.IsFalse(TSemVer.BestMatch([], '', LBest),               'empty list returns False');
end;

initialization
  TDUnitX.RegisterTestFixture(TSemVerTest);

end.
