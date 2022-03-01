#!/bin/sh

###############################################################################
 #
 #  This file is part of verkko-regression, a package that tests the Verkko
 #  whole-genome assembler.
 #
 #  Except as indicated otherwise, this is a 'United States Government Work',
 #  and is released in the public domain.
 #
 #  File 'README.licenses' in the root directory of this distribution
 #  contains full conditions and disclaimers.
 ##

#  Takes no arguments.

saveFile() {
    for arg in "$@" ; do
        dir=`dirname  $arg`
        nam=`basename $arg`

        if [ -e $dir/$nam ] ; then
            echo "  SAVE $arg"
            mkdir -p            ../../recipes/$asmn/refasm-$regr/$dir
            cp    -pr $dir/$nam ../../recipes/$asmn/refasm-$regr/$dir/$nam
        fi
    done
}

updateAssembly() {
    path=`pwd`
    asmn=`basename $path`
    regr=`dirname  $path`
    regr=`basename $regr`

    echo ""
    echo "In directory     '$path'"
    echo "Found assembly   '$asmn'"
    echo "Found regression '$regr'"

    if [ ! -e ./assembly.fasta ] ; then
      echo "  assembly not finished."
      return
    fi

    if [ -e ../../recipes/$asmn/refasm-$regr ] ; then
      echo "  refasm already exists in ../../recipes/$asmn/refasm-$regr"
      return
    fi

    mkdir -p ../../recipes/$asmn/refasm-$regr

    rm -f    ../../recipes/$asmn/refasm
    ln -s    refasm-$regr ../../recipes/$asmn/refasm


    #saveFile  asm.report

    #saveFile  asm.correctedReads.fasta.gz

    saveFile  assembly.fasta
    saveFile  assembly.gfa
    saveFile  assembly.layout
    saveFile  assembly.hifi-coverage.csv
    saveFile  assembly.ont-coverage.csv

    saveFile  quast/report.tsv
    saveFile  quast/contigs_reports/misassemblies_report.txt
    saveFile  quast/contigs_reports/transposed_report_misassemblies.txt
    saveFile  quast/contigs_reports/unaligned_report.txt
    saveFile  quast/contigs_reports/contigs_report_assembly.mis_contigs.info
    saveFile  quast/contigs_reports/contigs_report_assembly.unaligned.info
    saveFile  quast/contigs_reports/contigs_report_assembly.stdout
    saveFile  quast/contigs_reports/contigs_report_assembly.stdout.filtered

    echo "Reference assembly updated."
}


#  If no directory given, assume we're in the correct directory.
if [ $# -eq 0 -a ! -e "asm.seqStore" ] ; then
  echo "usage: $0 [assembly-directories]"
  echo "  If run in an assembly result directory, change the curated"
  echo "  result for this test to this assembly."
  echo ""
  echo "  If 'assembly-directories' are supplied, change the curated"
  echo "  result for those tests."
  echo ""
  echo "  If no assembly result is found (or if assembly-directory"
  echo "  isn't even a directory), nothing is done."
  echo ""
  echo "  examples:"
  echo "    % cd 2020-11-13-1306-master-76b1263fe840/ecoli-hifi-1"
  echo "    % sh ../../update-refasm.sh"
  echo ""
  echo "    % sh ./update-refasm.sh 2020-11-13-1306-master-76b1263fe840/*"
  echo ""
  echo ""
  exit
fi


#  If no directory given, assume we're in the correct directory.
if [ $# -eq 0 ] ; then
  updateAssembly
fi

#  But if directories on the command line, go into them first.
for dd in $@ ; do
  if [ -d $dd ] ; then
    if [ -e $dd/assembly.fasta ] ; then
      cd $dd
      updateAssembly
      cd -
    else
      echo ""
      echo "No contigs found in '$dd'."
    fi
  fi
done

echo ""
echo "Done!"

exit 0
