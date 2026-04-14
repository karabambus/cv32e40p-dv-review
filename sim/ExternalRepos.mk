###############################################################################
# Variables to generate the command to clone external repositories.
# For each repo there are a set of variables:
#      *_REPO:   URL to the repository (note, not all are in GitHub).
#      *_BRANCH: Name of the branch you wish to clone;
#                Set to 'master' to pull the master branch.
#      *_HASH:   Value of the specific hash you wish to clone;
#                Set to 'head' to pull the head of the branch you want.
#

export SHELL = /bin/bash

CV_CORE_REPO   ?= https://github.com/openhwgroup/cv32e40p
CV_CORE_BRANCH ?= master
CV_CORE_HASH   ?= 360d272898d81806be3377193870dbf83a3ea79f    # tag: cv32e40p_v1.8.3

# CV32E40P v1.0.0 (RTL Freeze 2020-12-10)
CV_CORE_V100_REPO   ?= https://github.com/openhwgroup/cv32e40p
CV_CORE_V100_BRANCH ?= master
CV_CORE_V100_HASH   ?= 120ac3ee79ef56a57fe07dd8701cd4ee94458fd5  # tag: cv32e40p_v1.0.0

CV_VERIF_REPO   ?= https://github.com/openhwgroup/core-v-verif
CV_VERIF_BRANCH ?= cv32e40p/dev
CV_VERIF_HASH   ?= head

RISCVDV_REPO    ?= https://github.com/google/riscv-dv
RISCVDV_BRANCH  ?= master
RISCVDV_HASH    ?= 0b625258549e733082c12e5dc749f05aefb07d5a

EMBENCH_REPO    ?= https://github.com/embench/embench-iot.git
EMBENCH_BRANCH  ?= master
EMBENCH_HASH    ?= 6934ddd1ff445245ee032d4258fdeb9828b72af4

# SVLIB
SVLIB_REPO       ?= https://bitbucket.org/verilab/svlib/src/master/svlib
SVLIB_BRANCH     ?= master
SVLIB_HASH       ?= c25509a7e54a880fe8f58f3daa2f891d6ecf6428

# COMPLIANCE (RISC-V Compliance Tests)
COMPLIANCE_REPO   ?= https://github.com/riscv/riscv-compliance
COMPLIANCE_BRANCH ?= master
COMPLIANCE_HASH   ?= c21a2e86afa3f7d4292a2dd26b759f3f29cde497

# ACT4 (RISC-V Architectural Certification Tests)
ACT4_REPO   ?= https://github.com/riscv/riscv-arch-test
ACT4_BRANCH ?= act4
ACT4_HASH   ?= d714306847303a0def3fe8df043257757867034c
