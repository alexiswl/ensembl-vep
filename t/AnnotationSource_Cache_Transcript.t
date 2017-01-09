# Copyright [2016] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Test::More;
use Test::Exception;
use FindBin qw($Bin);

use lib $Bin;
use VEPTestingConfig;
my $test_cfg = VEPTestingConfig->new();

## BASIC TESTS
##############

# use test
use_ok('Bio::EnsEMBL::VEP::AnnotationSource::Cache::Transcript');

my $dir = $test_cfg->{cache_dir};

# need to get a config object for further tests
use_ok('Bio::EnsEMBL::VEP::Config');

my $cfg = Bio::EnsEMBL::VEP::Config->new($test_cfg->base_testing_cfg);
ok($cfg, 'get new config object');

my $c = Bio::EnsEMBL::VEP::AnnotationSource::Cache::Transcript->new({
  config => $cfg,
  dir => $dir,
  source_type => 'ensembl',
  cache_region_size => 1000000,
  valid_chromosomes => [21],
});
ok($c, 'new is defined');


## METHODS
##########

is($c->serializer_type, 'storable', 'serializer_type');
is($c->file_suffix, 'gz', 'file_suffix');

is_deeply($c->get_valid_chromosomes, [21], 'get_valid_chromosomes');

is($c->get_dump_file_name(1, '1-100'), $dir.'/1/1-100.gz', 'get_dump_file_name');
is($c->get_dump_file_name(1, 1, 100), $dir.'/1/1-100.gz', 'get_dump_file_name with end');

throws_ok { $c->get_dump_file_name() } qr/No chromosome/, 'get_dump_file_name no chromosome';
throws_ok { $c->get_dump_file_name(1) } qr/No region/, 'get_dump_file_name no region';

$c->{sift} = 1;
$c->{info}->{sift} = '1';
ok($c->check_sift_polyphen, 'check_sift_polyphen');
$c->{info} = {};

no warnings 'once';
open(SAVE, ">&STDOUT") or die "Can't save STDOUT\n"; 

close STDOUT;
my $tmp;
open STDOUT, '>', \$tmp;

$c->{everything} = 1;
ok($c->check_sift_polyphen, 'check_sift_polyphen - everything 1');
is($c->{sift}, 0, 'check_sift_polyphen - everything 2');
ok($tmp =~ /disabling SIFT/, 'check_sift_polyphen - everything status_msg');
$c->{everything} = 0;
$c->{sift} = 1;

open(STDOUT, ">&SAVE") or die "Can't restore STDOUT\n";


throws_ok { $c->check_sift_polyphen } qr/SIFT not available/, 'check_sift_polyphen - fail';
delete($c->{sift});



# deserialization
my $obj = $c->deserialize_from_file(
  $c->get_dump_file_name(
    $test_cfg->{cache_chr},
    $test_cfg->{cache_region}
  )
);
is(ref($obj), 'HASH', 'deserialize_from_file ref 1 - PerlIO::gzip');
is(ref($obj->{$test_cfg->{cache_chr}}), 'ARRAY', 'deserialize_from_file ref 2 - PerlIO::gzip');
is(ref($obj->{$test_cfg->{cache_chr}}->[0]), 'Bio::EnsEMBL::Transcript', 'deserialize_from_file ref 3 - PerlIO::gzip');

my $perlio_gzip_bak = $Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized::CAN_USE_PERLIO_GZIP;
$Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized::CAN_USE_PERLIO_GZIP = 0;

$obj = $c->deserialize_from_file(
  $c->get_dump_file_name(
    $test_cfg->{cache_chr},
    $test_cfg->{cache_region}
  )
);
is(ref($obj), 'HASH', 'deserialize_from_file ref 1 - gzip');
is(ref($obj->{$test_cfg->{cache_chr}}), 'ARRAY', 'deserialize_from_file ref 2 - gzip');
is(ref($obj->{$test_cfg->{cache_chr}}->[0]), 'Bio::EnsEMBL::Transcript', 'deserialize_from_file ref 3 - gzip');

my $gzip_bak = $Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized::CAN_USE_GZIP;
$Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized::CAN_USE_GZIP = 0;

$obj = $c->deserialize_from_file(
  $c->get_dump_file_name(
    $test_cfg->{cache_chr},
    $test_cfg->{cache_region}
  )
);
is(ref($obj), 'HASH', 'deserialize_from_file ref 1 - Compress::Zlib');
is(ref($obj->{$test_cfg->{cache_chr}}), 'ARRAY', 'deserialize_from_file ref 2 - Compress::Zlib');
is(ref($obj->{$test_cfg->{cache_chr}}->[0]), 'Bio::EnsEMBL::Transcript', 'deserialize_from_file ref 3 - Compress::Zlib');

$Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized::CAN_USE_PERLIO_GZIP = $perlio_gzip_bak;
$Bio::EnsEMBL::VEP::AnnotationSource::Cache::BaseSerialized::CAN_USE_GZIP = $gzip_bak;



# processing deserialized object
my $features = $c->deserialized_obj_to_features($obj);
is(ref($features), 'ARRAY', 'deserialized_object_to_features ref 1');
is(ref($features->[0]), 'Bio::EnsEMBL::Transcript', 'deserialized_object_to_features ref 2');
is(ref($features->[-1]), 'Bio::EnsEMBL::Transcript', 'deserialized_object_to_features ref 3');
is(scalar @$features, 70, 'deserialized_object_to_features count');

# filter_transcript
is($c->filter_transcript($features->[0]), 1, 'filter_transcript pass');

$c->{gencode_basic} = 1;
is($c->filter_transcript($features->[3]), 0, 'filter_transcript fail gencode_basic');
$c->{gencode_basic} = 0;

$c->{source_type} = 'refseq';
is($c->filter_transcript($features->[0]), 0, 'filter_transcript fail all_refseq');

$features->[0]->{_source_cache} = 'RefSeq';
is($c->filter_transcript($features->[0]), 0, 'filter_transcript fail all_refseq merged');
$c->{source_type} = 'ensembl';

# check filter works on deserialized_obj_to_features
$c->{gencode_basic} = 1;
is(scalar @{$c->deserialized_obj_to_features($obj)}, 47, 'deserialized_object_to_features filtered count');
$c->{gencode_basic} = undef;

is(scalar @{$c->merge_features([@$features, @$features])}, 70, 'merge_features count');

# merge_features does some hacky data restoration
# probably only required for use with old buggy cache files
my @tmp = grep {$_->{_gene_symbol} eq 'MRPL39'} @$features;
delete $tmp[0]->{_gene_hgnc_id};
@tmp = @{$c->merge_features(\@tmp)};
is($tmp[0]->{_gene_hgnc_id}, 'HGNC:14027', 'merge_features restores missing _gene_hgnc_id');

$c->{source_type} = 'refseq';

# check copying/restoration of data
@tmp = grep {$_->{_gene_symbol} eq 'MRPL39'} @$features;
delete $tmp[0]->{$_} for qw(_gene_symbol _gene_symbol_source _gene_hgnc_id);
@tmp = @{$c->merge_features(\@tmp)};
is($tmp[0]->{_gene_symbol}, 'MRPL39', 'merge_features refseq restores missing _gene_symbol');
is($tmp[0]->{_gene_symbol_source}, 'HGNC', 'merge_features refseq restores missing _gene_symbol_source');
is($tmp[0]->{_gene_hgnc_id}, 'HGNC:14027', 'merge_features refseq restores missing _gene_hgnc_id');

# check removal of duplicates
@tmp = grep {$_->{_gene_symbol} eq 'MRPL39'} @$features;
my %copy = %{$tmp[-1]};
push @tmp, bless(\%copy, ref($tmp[-1]));
$tmp[-1]->{source} = 'ensembl';
$tmp[-1]->{dbID}++;
is(scalar @tmp, 4, 'merge_features refseq count before merge');
@tmp = @{$c->merge_features(\@tmp)};
is(scalar @tmp, 3, 'merge_features refseq removes duplicates');

$c->{source_type} = 'ensembl';

$features = $c->get_features_by_regions_uncached([[$test_cfg->{cache_chr}, $test_cfg->{cache_s}]]);
is(ref($features), 'ARRAY', 'get_features_by_regions_uncached ref 1');
is(ref($features->[0]), 'Bio::EnsEMBL::Transcript', 'get_features_by_regions_uncached ref 2');
is($features->[0]->stable_id, 'ENST00000441009', 'get_features_by_regions_uncached stable_id');

# now we should be able to retrieve the same from memory
$features = $c->get_features_by_regions_cached([[$test_cfg->{cache_chr}, $test_cfg->{cache_s}]]);
is(ref($features), 'ARRAY', 'get_features_by_regions_cached ref 1');
is(ref($features->[0]), 'Bio::EnsEMBL::Transcript', 'get_features_by_regions_cached ref 2');
is($features->[0]->stable_id, 'ENST00000441009', 'get_features_by_regions_cached stable_id');

$c->clean_cache();
is_deeply($c->cache, {}, 'clean_cache');



## TESTS WITH AN INPUT BUFFER
#############################

use_ok('Bio::EnsEMBL::VEP::Parser::VCF');
my $p = Bio::EnsEMBL::VEP::Parser::VCF->new({config => $cfg, file => $test_cfg->{test_vcf}, valid_chromosomes => [21]});
ok($p, 'get parser object');

use_ok('Bio::EnsEMBL::VEP::InputBuffer');
my $ib = Bio::EnsEMBL::VEP::InputBuffer->new({config => $cfg, parser => $p});
is(ref($ib), 'Bio::EnsEMBL::VEP::InputBuffer', 'check class');

is(ref($ib->next()), 'ARRAY', 'check buffer next');

is_deeply(
  $c->get_all_regions_by_InputBuffer($ib),
  [[21, 25]],
  'get_all_regions_by_InputBuffer'
);

$features = $c->get_all_features_by_InputBuffer($ib);
is(ref($features), 'ARRAY', 'get_all_features_by_InputBuffer ref 1');
is(ref($features->[0]), 'Bio::EnsEMBL::Transcript', 'get_all_features_by_InputBuffer ref 2');
is(ref($features->[-1]), 'Bio::EnsEMBL::Transcript', 'get_all_features_by_InputBuffer ref 3');
is($features->[0]->stable_id, 'ENST00000567517', 'get_all_features_by_InputBuffer stable_id');
is(scalar @$features, 44, 'get_all_features_by_InputBuffer count');

# do it again to get them from memory
$features = $c->get_all_features_by_InputBuffer($ib);
is($features->[0]->stable_id, 'ENST00000567517', 'get_all_features_by_InputBuffer again');

$ib->next();
is_deeply($c->get_all_features_by_InputBuffer($ib), [], 'get_all_features_by_InputBuffer on empty buffer');

# reset
$p = Bio::EnsEMBL::VEP::Parser::VCF->new({config => $cfg, file => $test_cfg->{test_vcf}, valid_chromosomes => [21]});
$ib = Bio::EnsEMBL::VEP::InputBuffer->new({config => $cfg, parser => $p});
$ib->next();

$c->annotate_InputBuffer($ib);
my $vf = $ib->buffer->[0];
my $tvs = $vf->get_all_TranscriptVariations;

is(scalar @$tvs, 3, 'annotate_InputBuffer - get_all_TranscriptVariations count');

$vf->_finish_annotation;
is($vf->display_consequence, 'missense_variant', 'annotate_InputBuffer - display_consequence');

## transcript filter
$c = Bio::EnsEMBL::VEP::AnnotationSource::Cache::Transcript->new({
  config => $cfg,
  dir => $dir,
  source_type => 'ensembl',
  cache_region_size => 1000000,
  valid_chromosomes => [21],
  filter => 'stable_id ne ENST00000352957',
});

$p = Bio::EnsEMBL::VEP::Parser::VCF->new({config => $cfg, file => $test_cfg->{test_vcf}, valid_chromosomes => [21]});
$ib = Bio::EnsEMBL::VEP::InputBuffer->new({config => $cfg, parser => $p});
$ib->next();

$c->annotate_InputBuffer($ib);
$vf = $ib->buffer->[0];
$vf->_finish_annotation;
is(scalar (grep {$_->transcript->stable_id eq 'ENST00000352957'} @{$vf->get_all_TranscriptVariations}), 0, 'with filter - filtered transcript absent');
is($vf->display_consequence, '3_prime_UTR_variant', 'with filter - display_consequence');


## SEREAL
#########

SKIP: {

  eval q{ use Sereal; };
  my $can_use_sereal = $@ ? 0 : 1;

  ## REMEMBER TO UPDATE THIS SKIP NUMBER IF YOU ADD MORE TESTS!!!!
  skip 'Sereal not installed', 6 unless $can_use_sereal;

  $c = Bio::EnsEMBL::VEP::AnnotationSource::Cache::Transcript->new({
    config => $cfg,
    dir => $test_cfg->{sereal_dir},
    serializer_type => 'sereal',
    source_type => 'ensembl'
  });

  is($c->serializer_type, 'sereal', 'sereal - serializer_type');
  is($c->file_suffix, 'sereal', 'file_suffix');

  # deserialization
  my $obj = $c->deserialize_from_file(
    $c->get_dump_file_name(
      $test_cfg->{cache_chr},
      $test_cfg->{cache_region}
    )
  );
  is(ref($obj), 'HASH', 'sereal - deserialize_from_file ref 1');
  is(ref($obj->{$test_cfg->{cache_chr}}), 'ARRAY', 'sereal - deserialize_from_file ref 2');
  is(ref($obj->{$test_cfg->{cache_chr}}->[0]), 'Bio::EnsEMBL::Transcript', 'sereal - deserialize_from_file ref 3');

  is($obj->{$test_cfg->{cache_chr}}->[0]->stable_id, 'ENST00000441009', 'sereal - deserialize_from_file stable_id');

  1;
}

# done
done_testing();
