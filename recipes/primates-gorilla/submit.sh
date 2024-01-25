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

syst=`uname -s`
arch=`uname -m | sed s/x86_64/amd64/`

#  To make this script a little bit less specific to each assembly,
#  it needs the name of the assembly as the only argument.

recp=$1

if [ x$recp = x ] ; then
  echo "usage: $0 <recp>"
  exit 1
fi

if [ ! -e "../recipes/$recp/verkko.sh" ] ; then
  echo "Failed to find '../recipes/$recp/verkko.sh'."
  exit 1
fi

if [ ! -e "../recipes/$recp/eval.sh" ] ; then
  echo "Failed to find '../recipes/$recp/eval.sh'."
  exit 1
fi

#
#  Submit two jobs, one to run the assembly and one to QC and report status.
#
#  But to do this, we need to figure out what grid type we have.
#  verkko/src/profiles/slurm-sge-submit.sh also has LSF support.
#    Slurm: if sinfo is present, assume slurm works.
#    SGE:   if SGE_CELL exists in the environment, assume SGE works.
#

slurm=`which sinfo 2> /dev/null`
sge=$SGE_CELL

n_cpus=1
mem_gb=8
time_h=96

if [ "x$slurm" != "x" ] ; then
  jobvid=$(sbatch --parsable                           --cpus-per-task 1 --mem  6g --time 96:00:00 --output $recp-verkko.out ../recipes/$recp/verkko.sh $recp)
  jobeid=$(sbatch --parsable --depend=afterany:$jobvid --cpus-per-task 8 --mem 32g --time 24:00:00 --output $recp-eval.out   ../recipes/$recp/eval.sh   $recp)

elif [ "x$sge" != "x" ] ; then
  jobvid=$(qsub -terse                   -cwd -V -pe thread 1 -l memory=6g -j y -o $recp-verkko.out ../recipes/$recp/verkko.sh $recp)
  jobeid=$(qsub -terse -hold_jid $jobvid -cwd -V -pe thread 8 -l memory=4g -j y -o $recp-eval.out   ../recipes/$recp/eval.sh   $recp)

else
  echo "Unknown grid; no jobs submitted."
  exit 1
fi

echo "Submitted verkko ($jobvid) and quast ($jobeid)."
exit 0
