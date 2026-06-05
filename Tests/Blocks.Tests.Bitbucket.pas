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
unit Blocks.Tests.Bitbucket;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Blocks.Bitbucket;

type
  [TestFixture]
  TBitbucketTest = class(TObject)
  public
    [Test]
    procedure TestGetZipUrlWithTag;
    [Test]
    procedure TestGetZipUrlWithCommit;
  end;

implementation

{ TBitbucketTest }

procedure TBitbucketTest.TestGetZipUrlWithTag;
begin
  Assert.AreEqual(
      'https://bitbucket.org/sglienke/spring4d/get/2.0.2.zip',
      TBitbucket.GetBitbucketZipUrl('sglienke', 'spring4d', '2.0.2')
  );
end;

procedure TBitbucketTest.TestGetZipUrlWithCommit;
begin
  Assert.AreEqual(
      'https://bitbucket.org/owner/repo/get/abc1234.zip',
      TBitbucket.GetBitbucketZipUrl('owner', 'repo', 'abc1234')
  );
end;

end.
