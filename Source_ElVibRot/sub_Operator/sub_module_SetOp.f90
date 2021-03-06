!===========================================================================
!===========================================================================
!This file is part of ElVibRot.
!
!    ElVibRot is free software: you can redistribute it and/or modify
!    it under the terms of the GNU General Public License as published by
!    the Free Software Foundation, either version 3 of the License, or
!    (at your option) any later version.
!
!    ElVibRot is distributed in the hope that it will be useful,
!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!    GNU General Public License for more details.
!
!    You should have received a copy of the GNU General Public License
!    along with ElVibRot.  If not, see <http://www.gnu.org/licenses/>.
!
!    Copyright 2015 David Lauvergnat [1]
!      with contributions of
!        Josep Maria Luis (optimization) [2]
!        Ahai Chen (MPI) [1,4]
!        Lucien Dupuy (CRP) [5]
!
![1]: Institut de Chimie Physique, UMR 8000, CNRS-Université Paris-Saclay, France
![2]: Institut de Química Computacional and Departament de Química,
!        Universitat de Girona, Catalonia, Spain
![3]: Department of Chemistry, Aarhus University, DK-8000 Aarhus C, Denmark
![4]: Maison de la Simulation USR 3441, CEA Saclay, France
![5]: Laboratoire Univers et Particule de Montpellier, UMR 5299,
!         Université de Montpellier, France
!
!    ElVibRot includes:
!        - Tnum-Tana under the GNU LGPL3 license
!        - Somme subroutines of John Burkardt under GNU LGPL license
!             http://people.sc.fsu.edu/~jburkardt/
!        - Somme subroutines of SHTOOLS written by Mark A. Wieczorek under BSD license
!             http://shtools.ipgp.fr
!        - Some subroutine of QMRPack (see cpyrit.doc) Roland W. Freund and Noel M. Nachtigal:
!             https://www.netlib.org/linalg/qmr/
!
!===========================================================================
!===========================================================================
MODULE mod_SetOp
      USE mod_system
      use mod_PrimOp, only: assignment(=),param_typeop, param_pes, dealloc_typeop,    &
                            write_typeop, param_d0matop, init_d0matop,  &
                            dealloc_d0matop

      USE mod_basis
      USE mod_ComOp
      USE mod_OpGrid
      USE mod_ReadOp
      IMPLICIT NONE

!------------------------------------------------------------------------------
        ! type param_Op
        TYPE, EXTENDS(param_TypeOp) :: param_Op

          logical                        :: init_var      = .FALSE.
          logical                        :: alloc         = .FALSE.

          logical                        :: alloc_Mat     = .FALSE.
          logical                        :: Mat_done      = .FALSE.
          logical                        :: Make_Mat      = .FALSE.
          logical                        :: Read_Mat      = .FALSE. ! if t=> the matrix is read
          logical                        :: sym_Hamil     = .TRUE.  ! if t => the Hamiltonian is symmetrized

          logical                        :: print_done = .FALSE. ! T if already print
          logical                        :: read_Op    = .FALSE. ! (def=f) if t=> the matrix operator will be read

          !-- for the basis set ----------------------------------------------
          TYPE (param_AllBasis), pointer :: para_AllBasis   => null() ! true POINTER
          TYPE (Basis),          pointer :: BasisnD,Basis2n => null() ! true POINTER
          integer                        :: symab           =  -1

          !-- for Tnum and mole ----------------------------------------------
          TYPE (CoordType),      pointer :: mole            => null() ! true POINTER
          TYPE (Tnum),           pointer :: para_Tnum       => null() ! true POINTER

          !-- for param_PES --------------------------------------------------
          TYPE (param_PES), pointer      :: para_PES        => null() ! true POINTER

!         !-- for ComOp ------------------------------------------------------
          TYPE (param_ComOp), pointer    :: ComOp           => null() ! true POINTER

          integer :: nb_OpPsi    = 0             ! number of Operator action

          integer :: nb_bie=0                    ! number of active basis functions and grid points
          integer :: nb_bi=0,nb_be=0             ! number of active basis functions and grid points
          integer :: nb_ba=0,nb_qa=0             ! number of active basis functions and grid points

          integer :: nb_bai=0,nb_qai=0           ! number of total active basis functions with HADA basis
          integer :: nb_baie=0,nb_qaie=0         ! number of total active basis functions
          integer :: nb_bRot=0                   ! number of total rotational basis functions
          integer :: nb_tot=0                    ! real size of the hamiltonian
                                                 ! can be smaller than nb_baie (HADA or spectral contracion)
          integer :: nb_tot_ini=0                ! size of the hamiltonian
                                                 ! can be smaller than nb_baie (HADA or spectral contracion)
                                                 ! usefull before the spectral transformation (for another operator)

          real (kind=Rkind),    pointer :: Rmat(:,:)   => null()        ! Rmat(nb_tot ,nb_tot )
          complex (kind=Rkind), pointer :: Cmat(:,:)   => null()        ! Cmat(nb_tot ,nb_tot )

          ! Parameters, when the matrix is packed
          integer, pointer              :: ind_Op(:,:) => null()        ! ind_Op(nb_tot,nb_tot)
          integer, pointer              :: dim_Op(:)   => null()        ! dim_Op(nb_tot)
          logical                       :: pack_Op     =  .FALSE.       ! default=f
          real (kind=Rkind)             :: tol_pack    =  ONETENTH**7   ! 1.d-7
          real (kind=Rkind)             :: ratio_pack  =  ZERO
          real (kind=Rkind)             :: tol_nopack  =  NINE*ONETENTH ! 0.9
                                                 ! no pack, if the packed ratio is larger

          ! Parameters for the diagonalization and the spectral representation
          logical                       :: spectral      = .FALSE.        ! if T, calculation of the sepctral representation
          logical                       :: spectral_done = .FALSE.        ! if T, The spect Rep is done
          integer                       :: spectral_Op   =  0             ! type of operator usually H (=>0)
          logical                       :: diago         = .FALSE.        ! if T, allocate the memory for diagonalization
          real (kind=Rkind),    pointer :: Rdiag(:)      => null()        ! Rdiag(nb_tot) : real eigenvalues
          complex (kind=Rkind), pointer :: Cdiag(:)      => null()        ! Cdiag(nb_tot ) : cplx eigenvalues
          real (kind=Rkind),    pointer :: Rvp(:,:)      => null()        ! Rvp(nb_tot ,nb_tot ) : real eigenvectors
          complex (kind=Rkind), pointer :: Cvp(:,:)      => null()        ! Cvp(nb_tot ,nb_tot ) : cplx eigenvectors


          integer                      :: nb_act1 = 0

          integer, allocatable         :: derive_termQdyn(:,:) ! (2,nb_Term)
          TYPE (param_OpGrid), pointer :: OpGrid(:)            => null() ! nb_Term
          TYPE (param_OpGrid), pointer :: imOpGrid(:)          => null() ! no more than 1


          logical                      :: alloc_Grid           = .FALSE.
          logical                      :: Grid_done            = .FALSE.
          TYPE (param_file)            :: file_Grid                    ! file of the grid
          TYPE (param_ReadOp)          :: para_ReadOp


          ! for H Operator n_Op = 0
          logical           :: scaled   = .FALSE.     ! if T scaled H
          real (kind=Rkind) :: E0       = ZERO        ! parameter for the scaling (for direct)
          real (kind=Rkind) :: Esc      = ONE         ! parameter for the scaling (for direct)

          real (kind=Rkind) :: Hmin     =  huge(ONE)  !
          real (kind=Rkind) :: Hmax     = -huge(ONE)  !

          real (kind=Rkind)              :: pot0              = ZERO    !
          logical                        :: pot_only          = .FALSE. ! comput only the PES without T (and the vep)
          logical                        :: T_only            = .FALSE. ! comput only the T (with the vep)
          logical                        :: SplitH            = .FALSE. ! When true, the H is split in a diagonal part wich contains the KEO and also part of the potential (for HO basis set)
          real (kind=Rkind), allocatable :: SplitDiagB(:)               ! if SplitH=t, the Hamiltonian diagonal values on the basis set

        END TYPE param_Op

!-------------------------------------------------------------------------------
      !!@description: TODO
      !!@param: TODO
        TYPE param_AllOp

          integer                  :: nb_Op     =  0
          TYPE (param_Op), pointer :: tab_Op(:) => null()

        END TYPE param_AllOp
!-------------------------------------------------------------------------------

      INTERFACE alloc_array
        MODULE PROCEDURE alloc_array_OF_Opdim1
      END INTERFACE

      INTERFACE dealloc_array
        MODULE PROCEDURE dealloc_array_OF_Opdim1
      END INTERFACE

      CONTAINS


!=======================================================================================
!
!  allocate/deallocate para_Op
!
!=======================================================================================
      !!@description: TODO
      !!@param: TODO
      !!@param: TODO
      !!@param: TODO
      SUBROUTINE alloc_para_Op(para_Op,Grid,Mat,Grid_cte)
      USE mod_MPI
      TYPE (param_Op), intent(inout) :: para_Op
      logical, optional, intent(in) :: Mat,Grid
      logical, optional, intent(in) :: Grid_cte(para_Op%nb_term)

      logical :: SmolyakRep,lo_Mat,lo_Grid,lo_Grid_cte(para_Op%nb_term)
      integer :: nb_tot,nb_SG,nb_SG1,nb_SG2
      integer :: nb_term,nb_bie

      integer :: err


      character(len=:), allocatable     :: info
      integer :: k_term


!----- for debuging --------------------------------------------------
      integer :: err_mem,memory
      logical, parameter :: debug = .FALSE.
      !logical, parameter :: debug = .TRUE.
      character (len=*), parameter :: name_sub='alloc_para_Op'
!---------------------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        IF (present(Mat))      write(out_unitp,*) 'alloc Mat?',Mat
        IF (present(Grid))     write(out_unitp,*) 'alloc Grid?',Grid
        IF (present(Grid_cte)) write(out_unitp,*) 'Grid_cte?',Grid_cte

        write(out_unitp,*) 'nb_term',para_Op%nb_term

        !CALL write_param_Op(para_Op)
        write(out_unitp,*)
      END IF
!---------------------------------------------------------------------

      IF (.NOT. para_Op%init_var) THEN
        write(out_unitp,*) ' ERROR in ',name_sub
        write(out_unitp,*) ' para_Op has NOT been initiated: init_var=F'
        write(out_unitp,*) ' CHECK the source!!!!!'
        CALL write_param_Op(para_Op)
        STOP
      END IF

      SmolyakRep = ( para_Op%BasisnD%SparseGrid_type == 4)
      nb_SG      = para_Op%BasisnD%nb_SG
#if(run_MPI)      
      ! nb_SG1,nb_SG2 for MPI 
      IF(nb_SG>0) THEN
        nb_per_MPI=para_Op%BasisnD%nb_SG/MPI_np
        !If(mod(para_Op%BasisnD%nb_SG,MPI_np)/=0) nb_per_MPI=nb_per_MPI+1
        !nb_SG1=MPI_id*nb_per_MPI+1
        !nb_SG2=MIN((MPI_id+1)*nb_per_MPI,para_Op%BasisnD%nb_SG)
        nb_rem_MPI=mod(para_Op%BasisnD%nb_SG,MPI_np)
        nb_SG1=MPI_id*nb_per_MPI+1+MIN(MPI_id,nb_rem_MPI)
        nb_SG2=(MPI_id+1)*nb_per_MPI+MIN(MPI_id,nb_rem_MPI)+merge(1,0,nb_rem_MPI>MPI_id)
        nb_SG=nb_SG2-nb_SG1+1
        write(out_unitp,*) 'nb_SG,nb_SG1,nb_SG2,total:',nb_SG,nb_SG1,nb_SG2,           &
                            para_Op%BasisnD%nb_SG,' from ',MPI_id
      ENDIF
#endif

      IF (present(Mat)) THEN
        lo_Mat = Mat
      ELSE
        lo_Mat = .TRUE.
      END IF

      IF (present(Grid)) THEN
        lo_Grid = Grid
      ELSE
        lo_Grid = .FALSE.
      END IF

      IF (present(Grid_cte)) THEN
        lo_Grid_cte(:) = Grid_cte(:)
      ELSE
        lo_Grid_cte(:) = .FALSE.
      END IF

      IF (debug) THEN
        write(out_unitp,*) ' alloc ...:,Mat,Grid',lo_Mat,lo_Grid
        write(out_unitp,*) ' Grid_cte: ',lo_Grid_cte(:)
      END IF

      para_Op%alloc = .TRUE.

      nb_tot  = para_Op%nb_tot
      nb_term = para_Op%nb_term
      nb_bie  = get_nb_be_FROM_Op(para_Op) * para_Op%nb_bi


      IF (nb_tot < 1) THEN
        write(out_unitp,*) ' ERROR in ',name_sub
        write(out_unitp,*) ' nb_tot is <1',nb_tot
        CALL write_param_Op(para_Op)
        STOP
      END IF

      IF (lo_mat) THEN
        para_Op%alloc_mat = .TRUE.
        IF (para_Op%cplx) THEN
          IF (.NOT. associated(para_Op%Cmat) ) THEN
             CALL alloc_array(para_Op%Cmat,(/ nb_tot,nb_tot /),         &
                             'para_Op%Cmat',name_sub)
          END IF

        ELSE
          IF (.NOT. associated(para_Op%Rmat) ) THEN
             CALL alloc_array(para_Op%Rmat,(/ nb_tot,nb_tot /),         &
                             'para_Op%Rmat',name_sub)
          END IF
        END IF
        IF (para_Op%pack_Op) THEN
          IF (.NOT. associated(para_Op%ind_Op) ) THEN
             CALL alloc_array(para_Op%ind_Op,(/ nb_tot,nb_tot /),       &
                             'para_Op%ind_Op',name_sub)
          END IF
          IF (.NOT. associated(para_Op%dim_Op) ) THEN
             CALL alloc_array(para_Op%dim_Op,(/ nb_tot /),              &
                             'para_Op%dim_Op',name_sub)
          END IF
        END IF
      END IF

      IF (lo_mat .AND. para_Op%diago) THEN
        IF (para_Op%cplx) THEN
          IF (.NOT. associated(para_Op%Cdiag) ) THEN
             CALL alloc_array(para_Op%Cdiag,(/ nb_tot /),               &
                             'para_Op%Cdiag',name_sub)
          END IF
          IF (.NOT. associated(para_Op%Cvp) ) THEN
             CALL alloc_array(para_Op%Cvp,(/ nb_tot,nb_tot /),          &
                             'para_Op%Cvp',name_sub)
          END IF
        ELSE
          IF (.NOT. associated(para_Op%Rdiag) ) THEN
             CALL alloc_array(para_Op%Rdiag,(/ nb_tot /),               &
                             'para_Op%Rdiag',name_sub)
          END IF
          IF (.NOT. associated(para_Op%Rvp) ) THEN
             CALL alloc_array(para_Op%Rvp,(/ nb_tot,nb_tot /),          &
                              'para_Op%Rvp',name_sub)
          END IF
        END IF
      END IF

      IF (lo_Grid) THEN
        para_Op%alloc_Grid = .TRUE.

        IF (.NOT. associated(para_Op%OpGrid)) THEN
          CALL alloc_array(para_Op%OpGrid,(/nb_term/),"para_Op%OpGrid",name_sub)
          para_Op%OpGrid(:)%grid_cte = lo_Grid_cte(:)

          ! special case for scalar part (potential ...)
          k_term = para_Op%derive_term_TO_iterm(0,0)
          IF (para_Op%direct_ScalOp) THEN
            para_Op%OpGrid(k_term)%para_FileGrid%Save_MemGrid = .FALSE.
          END IF

          DO k_term=1,para_Op%nb_term
            para_Op%OpGrid(k_term)%para_FileGrid = para_Op%para_ReadOp%para_FileGrid

            info = String_TO_String('  k_term( ' // int_TO_char(k_term) // &
                                      ' ) of ' // trim(para_Op%name_Op))

#if(run_MPI)
            CALL alloc_OpGrid(para_Op%OpGrid(k_term),                 &
                              para_Op%nb_qa,nb_bie,                   &
                              para_Op%derive_termQact(:,k_term),      &
                              para_Op%derive_termQdyn(:,k_term),      &
                              SmolyakRep,nb_SG1,nb_SG2,info)
#else
            CALL alloc_OpGrid(para_Op%OpGrid(k_term),                 &
                              para_Op%nb_qa,nb_bie,                   &
                              para_Op%derive_termQact(:,k_term),      &
                              para_Op%derive_termQdyn(:,k_term),      &
                              SmolyakRep,nb_SG,info)
#endif

            deallocate(info)
          END DO
        END IF
        IF (.NOT. associated(para_Op%imOpGrid) .AND. para_Op%cplx) THEN

          CALL alloc_array(para_Op%imOpGrid,(/1/),                      &
                          "para_Op%imOpGrid",name_sub)

          para_Op%imOpGrid(1)%para_FileGrid = para_Op%para_ReadOp%para_FileGrid

          ! special case for scalar part (potential ...)
          IF (para_Op%direct_ScalOp) THEN
            para_Op%imOpGrid(1)%para_FileGrid%Save_MemGrid = .FALSE.
          END IF

          info = String_TO_String(' of ' // trim(para_Op%name_Op))

#if(run_MPI)
          CALL alloc_OpGrid(para_Op%imOpGrid(1),                      &
                            para_Op%nb_qa,nb_bie,                     &
                            (/ 0,0 /),(/ 0,0 /),SmolyakRep,nb_SG1,nb_SG2,info)
#else
          CALL alloc_OpGrid(para_Op%imOpGrid(1),                      &
                            para_Op%nb_qa,nb_bie,                     &
                            (/ 0,0 /),(/ 0,0 /),SmolyakRep,nb_SG,info)
#endif
          para_Op%imOpGrid(1)%cplx = .TRUE.

          deallocate(info)

        END IF
      END IF
!---------------------------------------------------------------------
      IF (debug) THEN
        para_Op%print_done = .FALSE.
        CALL write_param_Op(para_Op)
        write(out_unitp,*) 'END ',name_sub
      END IF
!---------------------------------------------------------------------

      END SUBROUTINE alloc_para_Op
!=======================================================================================

      !!@description: TODO
      !!@param: TODO
      !!@param: TODO
      !!@param: TODO
      SUBROUTINE dealloc_para_Op(para_Op,keep_init)
      USE mod_MPI
      TYPE (param_Op),          intent(inout) :: para_Op
      logical,        optional, intent(in)    :: keep_init

      integer :: k_term
      logical :: keep_init_loc

      integer :: err_mem,memory
      character (len=*), parameter :: name_sub='dealloc_para_Op'

      !IF (.NOT. para_Op%alloc) RETURN

      keep_init_loc = .FALSE.
      IF (present(keep_init)) keep_init_loc = keep_init

      IF (associated(para_Op%Rmat))    THEN
        CALL dealloc_array(para_Op%Rmat,'para_Op%Rmat',name_sub)
      END IF
      IF (associated(para_Op%Cmat))    THEN
        CALL dealloc_array(para_Op%Cmat,'para_Op%Cmat',name_sub)
      END IF
      IF (associated(para_Op%ind_Op))  THEN
        CALL dealloc_array(para_Op%ind_Op,'para_Op%ind_Op',name_sub)
      END IF
      IF (associated(para_Op%dim_Op))  THEN
        CALL dealloc_array(para_Op%dim_Op,'para_Op%dim_Op',name_sub)
      END IF


      IF (associated(para_Op%Rdiag))  THEN
        CALL dealloc_array(para_Op%Rdiag,'para_Op%Rdiag',name_sub)
      END IF
      IF (associated(para_Op%Cdiag))  THEN
        CALL dealloc_array(para_Op%Cdiag,'para_Op%Cdiag',name_sub)

      END IF
      IF (associated(para_Op%Rvp))    THEN
        CALL dealloc_array(para_Op%Rvp,'para_Op%Rvp',name_sub)
      END IF
      IF (associated(para_Op%Cvp))    THEN
        CALL dealloc_array(para_Op%Cvp,'para_Op%Cvp',name_sub)
      END IF

      IF (.NOT. keep_init_loc) THEN
        CALL dealloc_TypeOp(para_Op%param_TypeOp)

        IF (allocated(para_Op%derive_termQdyn))  THEN
          CALL dealloc_NParray(para_Op%derive_termQdyn,'para_Op%derive_termQdyn',name_sub)
        END IF
      END IF


      IF (associated(para_Op%OpGrid)) THEN
        DO k_term=1,para_Op%nb_term
          CALL dealloc_OpGrid(para_Op%OpGrid(k_term),para_Op%para_ReadOp%para_FileGrid%keep_FileGrid)
        END DO
        CALL dealloc_array(para_Op%OpGrid,"para_Op%OpGrid",name_sub)
      END IF
      IF (associated(para_Op%imOpGrid)) THEN
        CALL dealloc_OpGrid(para_Op%imOpGrid(1),para_Op%para_ReadOp%para_FileGrid%keep_FileGrid)
        CALL dealloc_array(para_Op%imOpGrid,"para_Op%imOpGrid",name_sub)
      END IF

      para_Op%alloc      = .FALSE.
      para_Op%alloc_mat  = .FALSE.
      para_Op%mat_done   = .FALSE.
      para_Op%alloc_Grid = .FALSE.
      para_Op%Grid_done  = .FALSE.

      IF (.NOT. keep_init_loc) THEN
        para_Op%read_Op    = .FALSE.
        para_Op%print_done = .FALSE.

        para_Op%init_var = .FALSE.

        nullify(para_Op%para_AllBasis)
        nullify(para_Op%BasisnD)
        nullify(para_Op%Basis2n)

        para_Op%symab = -1

        nullify(para_Op%mole)
        nullify(para_Op%para_Tnum)

        nullify(para_Op%para_PES)

        nullify(para_Op%ComOp)

        para_Op%n_Op        = 0
        para_Op%name_Op     = 'H'

        para_Op%Make_Mat    = .FALSE.
        CALL init_ReadOp(para_Op%para_ReadOp)
        para_Op%cplx        = .FALSE.
        para_Op%sym_Hamil   = .TRUE.

        para_Op%spectral    = .FALSE.
        para_Op%spectral_Op = 0
        para_Op%nb_OpPsi    = 0


        para_Op%nb_bi       = 0
        para_Op%nb_be       = 0
        para_Op%nb_bie      = 0
        para_Op%nb_ba       = 0
        para_Op%nb_qa       = 0
        para_Op%nb_bai      = 0
        para_Op%nb_qai      = 0
        para_Op%nb_baie     = 0
        para_Op%nb_qaie     = 0
        para_Op%nb_bRot     = 0
        para_Op%nb_tot      = 0
        para_Op%nb_tot_ini  = 0


        para_Op%pack_Op = .FALSE.
        para_Op%tol_pack= ONETENTH**7
        para_Op%ratio_pack= ZERO
        para_Op%tol_nopack= NINE*ONETENTH

        para_Op%diago   = .FALSE.


        para_Op%nb_act1 = 0

        ! for H Operator n_Op = 0
        para_Op%scaled      = .FALSE.
        para_Op%E0          = ZERO
        para_Op%Esc         = ONE


        para_Op%pot0        = ZERO
        para_Op%pot_only    = .FALSE.
        para_Op%T_only      = .FALSE.

      END IF

      ! for H Operator n_Op = 0
      para_Op%Hmin        =  huge(ONE)
      para_Op%Hmax        = -huge(ONE)

      END SUBROUTINE dealloc_para_Op

!===============================================================================
! ++    write the type param_Op
!===============================================================================
      SUBROUTINE write_param_Op(para_Op)
      USE mod_system
      IMPLICIT NONE

      TYPE (param_Op)   :: para_Op
      integer           :: i,iOp


      IF (print_level <= 0 .OR. para_Op%print_done) RETURN

      para_Op%print_done = .TRUE.
      write(out_unitp,*) 'WRITE param_Op'

      write(out_unitp,*) 'asso para_AllBasis',associated(para_Op%para_AllBasis)
      write(out_unitp,*) 'asso BasisnD',associated(para_Op%BasisnD)
      write(out_unitp,*) 'asso Basis2n',associated(para_Op%Basis2n)

      write(out_unitp,*) 'asso mole',associated(para_Op%mole)
      write(out_unitp,*) 'asso para_Tnum',associated(para_Op%para_Tnum)
      write(out_unitp,*) 'asso para_PES',associated(para_Op%para_PES)
      write(out_unitp,*) 'asso ComOp',associated(para_Op%ComOp)

      write(out_unitp,*)
      write(out_unitp,*) 'n_Op,name',para_Op%n_Op,para_Op%name_Op
      write(out_unitp,*) 'alloc,mat_done ',para_Op%alloc,para_Op%mat_done
      CALL flush_perso(out_unitp)
      write(out_unitp,*) 'Read_Op ',para_Op%read_Op
      write(out_unitp,*) 'Make_Mat ',para_Op%Make_Mat
      write(out_unitp,*) 'sym_Hamil ',para_Op%sym_Hamil

      write(out_unitp,*) 'cplx',para_Op%cplx

      CALL Write_TypeOp(para_Op%param_TypeOp)

      write(out_unitp,*) 'spectral,spectral_Op',                        &
                  para_Op%spectral,para_Op%spectral_Op

      write(out_unitp,*)
      write(out_unitp,*) 'nb_tot',para_Op%nb_tot
      write(out_unitp,*) 'nb_tot_ini',para_Op%nb_tot_ini
      write(out_unitp,*) 'symab, bits(symab)',                          &
                                      WriteTOstring_symab(para_Op%symab)

      write(out_unitp,*) 'nb_ba,nb_qa',para_Op%nb_ba,para_Op%nb_qa
      write(out_unitp,*) 'nb_bi,nb_be',para_Op%nb_bi,para_Op%nb_be
      write(out_unitp,*) 'nb_bai,nb_qai',para_Op%nb_bai,para_Op%nb_qai
      write(out_unitp,*) 'nb_baie,nb_qaie',para_Op%nb_baie,para_Op%nb_qaie
      write(out_unitp,*) 'asso Rmat',associated(para_Op%Rmat)
      IF (associated(para_Op%Rmat)) write(out_unitp,*) shape(para_Op%Rmat)
      write(out_unitp,*) 'asso Cmat',associated(para_Op%Cmat)
      IF (associated(para_Op%Cmat)) write(out_unitp,*) shape(para_Op%Cmat)
      write(out_unitp,*) 'pack_Op,tol_pack',para_Op%pack_Op,para_Op%tol_pack
      write(out_unitp,*) 'tol_nopack',para_Op%tol_nopack
      write(out_unitp,*) 'ratio_pack',para_Op%ratio_pack
      write(out_unitp,*) 'asso ind_Op',associated(para_Op%ind_Op)
      IF (associated(para_Op%ind_Op)) write(out_unitp,*) shape(para_Op%ind_Op)
      write(out_unitp,*) 'asso dim_Op',associated(para_Op%dim_Op)
      IF (associated(para_Op%dim_Op)) write(out_unitp,*) shape(para_Op%dim_Op)

      write(out_unitp,*) 'diago',para_Op%diago
      write(out_unitp,*) 'asso Cdiag',associated(para_Op%Cdiag)
      IF (associated(para_Op%Cdiag)) write(out_unitp,*) shape(para_Op%Cdiag)
      write(out_unitp,*) 'asso Cvp',associated(para_Op%Cvp)
      IF (associated(para_Op%Cvp)) write(out_unitp,*) shape(para_Op%Cvp)
      write(out_unitp,*) 'asso Rdiag',associated(para_Op%Rdiag)
      IF (associated(para_Op%Rdiag)) write(out_unitp,*) shape(para_Op%Rdiag)
      write(out_unitp,*) 'asso Rvp',associated(para_Op%Rvp)
      IF (associated(para_Op%Rvp)) write(out_unitp,*) shape(para_Op%Rvp)


      write(out_unitp,*) 'nb_act1',para_Op%nb_act1
      write(out_unitp,*) 'nb_term',para_Op%nb_term
      write(out_unitp,*) 'nb_Term_Rot',para_Op%nb_Term_Rot
      write(out_unitp,*) 'nb_Term_Vib',para_Op%nb_Term_Vib

      write(out_unitp,*) 'allo ...derive_termQact',allocated(para_Op%derive_termQact)
      IF (allocated(para_Op%derive_termQact)) THEN
        DO i=1,ubound(para_Op%derive_termQact,dim=2)
          write(out_unitp,*) 'Op term',i,'der',para_Op%derive_termQact(:,i)
        END DO
      END IF
      write(out_unitp,*) 'allo ...derive_termQdyn',allocated(para_Op%derive_termQdyn)
      IF (allocated(para_Op%derive_termQdyn)) THEN
        DO i=1,ubound(para_Op%derive_termQact,dim=2)
          write(out_unitp,*) 'Op term',i,'der',para_Op%derive_termQdyn(:,i)
        END DO
      END IF
      CALL flush_perso(out_unitp)

      write(out_unitp,*) 'para_FileGrid'
      CALL Write_FileGrid(para_Op%para_ReadOp%para_FileGrid)
      CALL flush_perso(out_unitp)

      write(out_unitp,*) 'asso ...Grid',associated(para_Op%OpGrid)
      IF (associated(para_Op%OpGrid))                                   &
                              write(out_unitp,*) shape(para_Op%OpGrid)
      CALL flush_perso(out_unitp)
      write(out_unitp,*) 'asso ...imGrid',associated(para_Op%imOpGrid)
      CALL flush_perso(out_unitp)

      IF (associated(para_Op%OpGrid)) THEN
        DO iOp=1,size(para_Op%OpGrid)
           write(out_unitp,*) 'param of para_Op%OpGrid(iOp)',iOp
           CALL flush_perso(out_unitp)
          CALL Write_OpGrid(para_Op%OpGrid(iOp))
        END DO
      END IF
      CALL flush_perso(out_unitp)


      IF (para_Op%n_Op == 0) THEN
        write(out_unitp,*) 'for H Operator n_Op = 0'
        write(out_unitp,*) 'scaled,E0,Esc',para_Op%scaled,para_Op%E0,para_Op%Esc
        write(out_unitp,*) 'Hmin,Hmax ',para_Op%Hmin,para_Op%Hmax
        write(out_unitp,*) 'pot0 ',para_Op%pot0
        write(out_unitp,*) 'pot_only,T_only ',para_Op%pot_only,para_Op%T_only
      END IF
      CALL flush_perso(out_unitp)

      CALL write_param_ComOp(para_Op%ComOp)

          !TYPE (param_file)            :: file_Grid                    ! file of the grid
          !TYPE (param_ReadOp)          :: para_ReadOp

      write(out_unitp,*) 'END WRITE param_Op'
      CALL flush_perso(out_unitp)

      END SUBROUTINE write_param_Op
!===============================================================================

      !!@description: TODO
      !!@param: TODO
      !!@param: TODO
      !!@param: TODO
      SUBROUTINE dealloc_para_AllOp(para_AllOp)
      TYPE (param_AllOp), intent(inout) :: para_AllOp

      integer :: i

      IF (associated(para_AllOp%tab_Op)) THEN
        DO i=1,size(para_AllOp%tab_Op)
          CALL dealloc_para_Op(para_AllOp%tab_Op(i))
        END DO

        CALL dealloc_array(para_AllOp%tab_Op,'para_AllOp%tab_Op','dealloc_para_AllOp')

      END IF
      para_AllOp%nb_Op = 0

      END SUBROUTINE dealloc_para_AllOp

!=======================================================================================
      SUBROUTINE alloc_array_OF_Opdim1(tab,tab_ub,name_var,name_sub,tab_lb)
      USE mod_MPI
      IMPLICIT NONE

      TYPE (param_Op), pointer, intent(inout) :: tab(:)
      integer,                  intent(in)    :: tab_ub(:)
      integer, optional,        intent(in)    :: tab_lb(:)
      character (len=*),        intent(in)    :: name_var,name_sub

      integer, parameter :: ndim=1
      logical :: memory_test

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub_alloc = 'alloc_array_OF_Opdim1'
      integer :: err_mem,memory
      logical,parameter :: debug=.FALSE.
!      logical,parameter :: debug=.TRUE.
!----- for debuging --------------------------------------------------


       IF (associated(tab))                                             &
             CALL Write_error_NOT_null(name_sub_alloc,name_var,name_sub)

       CALL sub_test_tab_ub(tab_ub,ndim,name_sub_alloc,name_var,name_sub)

       IF (present(tab_lb)) THEN
         CALL sub_test_tab_lb(tab_lb,ndim,name_sub_alloc,name_var,name_sub)

         memory = product(tab_ub(:)-tab_lb(:)+1)
         allocate(tab(tab_lb(1):tab_ub(1)),stat=err_mem)
       ELSE
         memory = product(tab_ub(:))
         allocate(tab(tab_ub(1)),stat=err_mem)
       END IF
       CALL error_memo_allo(err_mem,memory,name_var,name_sub,'param_Op')

      END SUBROUTINE alloc_array_OF_Opdim1
!=======================================================================================

      SUBROUTINE dealloc_array_OF_Opdim1(tab,name_var,name_sub)
      IMPLICIT NONE

      TYPE (param_Op), pointer, intent(inout) :: tab(:)
      character (len=*), intent(in) :: name_var,name_sub

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub_alloc = 'dealloc_array_OF_Opdim1'
      integer :: err_mem,memory
      logical,parameter :: debug=.FALSE.
!      logical,parameter :: debug=.TRUE.
!----- for debuging --------------------------------------------------

       !IF (.NOT. associated(tab)) RETURN
       IF (.NOT. associated(tab))                                       &
             CALL Write_error_null(name_sub_alloc,name_var,name_sub)

       memory = size(tab)
       deallocate(tab,stat=err_mem)
       CALL error_memo_allo(err_mem,-memory,name_var,name_sub,'param_Op')
       nullify(tab)

      END SUBROUTINE dealloc_array_OF_Opdim1

      FUNCTION get_nb_be_FROM_Op(para_Op)
      USE mod_system
      IMPLICIT NONE

      integer :: get_nb_be_FROM_Op
!----- variables for the construction of H ---------------------------
      TYPE (param_Op), intent(in) :: para_Op

      integer :: ib
!----- for debuging --------------------------------------------------
      !logical, parameter :: debug = .TRUE.
       logical, parameter :: debug = .FALSE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING get_nb_be_FROM_Op'
      END IF

     IF (NewBasisEl) THEN
       get_nb_be_FROM_Op = get_nb_be_FROM_basis(para_Op%BasisnD)
       IF (get_nb_be_FROM_Op == -1) THEN
         write(out_unitp,*) ' ERROR in get_nb_be_FROM_Op'
         write(out_unitp,*) ' NewBasisEl = t and no El basis set!!'
         write(out_unitp,*) ' CHECK the source'
         STOP
       END IF
     ELSE IF (associated(para_Op%ComOp)) THEN
       get_nb_be_FROM_Op = para_Op%ComOp%nb_be
     ELSE
       write(out_unitp,*) ' ERROR in get_nb_be_FROM_Op'
       write(out_unitp,*) ' para_Op%ComOp in not associated'
       write(out_unitp,*) ' CHECK the source'
       STOP
     END IF

      IF (debug) THEN
        write(out_unitp,*) 'END get_nb_be_FROM_Op'
      END IF
      END FUNCTION get_nb_be_FROM_Op
!
!================================================================
! ++    Copy ComOp,para_H in ComOp_HADA,para_H_HADA
!       for the HADA channel i_bi
!
!================================================================
!
      !!@description: TODO
      !!@param: TODO
      !!@param: TODO
      !!@param: TODO
      SUBROUTINE param_HTOparam_H_HADA(i_bi,para_H,para_H_HADA)

!----- variables for the construction of H ---------------------------
      TYPE (param_Op)    :: para_H,para_H_HADA


      integer            :: i_bi
      integer            :: nb_act1,nb_ba,nb_bie,nb_basis_act1
      integer            :: na(2)

      integer            :: k_term

!----- for debuging --------------------------------------------------
      integer :: err_mem,memory
      character (len=*), parameter :: name_sub = 'param_HTOparam_H_HADA'

      logical,parameter :: debug=.FALSE.
!     logical,parameter :: debug=.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'i_bi',i_bi
        CALL write_param_Op(para_H)
      END IF
!-----------------------------------------------------------

      para_H_HADA%init_var = .TRUE.
      para_H_HADA%alloc    = .FALSE.
      para_H_HADA%mat_done = .FALSE.

      IF (associated(para_H%para_AllBasis)) THEN
        para_H_HADA%para_AllBasis => para_H%para_AllBasis
      ELSE
        nullify(para_H_HADA%para_AllBasis)
      END IF
      IF (associated(para_H%BasisnD)) THEN
        para_H_HADA%BasisnD => para_H%BasisnD
      ELSE
        nullify(para_H_HADA%BasisnD)
      END IF
      IF (associated(para_H%Basis2n)) THEN
        para_H_HADA%Basis2n => para_H%Basis2n
      ELSE
        nullify(para_H_HADA%Basis2n)
      END IF
      para_H_HADA%symab = para_H%symab


      IF (associated(para_H%mole)) THEN
        para_H_HADA%mole      => para_H%mole
      ELSE
        nullify(para_H_HADA%mole)
      END IF
      IF (associated(para_H%para_Tnum)) THEN
        para_H_HADA%para_Tnum => para_H%para_Tnum
      ELSE
        nullify(para_H_HADA%para_Tnum)
      END IF


      IF (associated(para_H%para_PES)) THEN
        para_H_HADA%para_PES  => para_H%para_PES
      ELSE
        nullify(para_H_HADA%para_PES)
      END IF

!     - for param_TypeOp of para_H_HADA ------------------
      para_H_HADA%param_TypeOp = para_H%param_TypeOp

      CALL alloc_NParray(para_H_HADA%derive_termQdyn,                   &
                                          (/ 2,para_H_HADA%nb_term /),  &
                        'para_H_HADA%derive_termQdyn',name_sub)
      para_H_HADA%derive_termQdyn(:,:) = para_H%derive_termQdyn(:,:)

!     - for ComOp of para_H_HADA ------------------

      nb_act1 = para_H%ComOp%nb_act1
      nb_ba   = para_H%ComOp%nb_ba
      nb_bie  = para_H%ComOp%nb_bie

      para_H_HADA%ComOp%nb_act1 = nb_act1
      para_H_HADA%ComOp%nb_ba   = nb_ba
      para_H_HADA%ComOp%nb_bi   = 1
      para_H_HADA%ComOp%nb_be   = 1
      para_H_HADA%ComOp%nb_bie  = 1

      para_H_HADA%ComOp%contrac_ba_ON_HAC       = .FALSE.
      para_H_HADA%ComOp%max_nb_ba_ON_HAC        = nb_ba

      CALL alloc_array(para_H_HADA%ComOp%nb_ba_ON_HAC,(/ 1 /),          &
                      'para_H_HADA%ComOp%nb_ba_ON_HAC',name_sub)
      para_H_HADA%ComOp%nb_ba_ON_HAC(1) = nb_ba

      CALL alloc_array(para_H_HADA%ComOp%d0Cba_ON_HAC,(/ nb_ba,nb_ba,1 /),&
                      'para_H_HADA%ComOp%d0Cba_ON_HAC',name_sub)
      CALL mat_id(para_H_HADA%ComOp%d0Cba_ON_HAC(:,:,1),nb_ba,nb_ba)

      CALL alloc_array(para_H_HADA%ComOp%Eneba_ON_HAC,(/ nb_ba,1 /),    &
                      'para_H_HADA%ComOp%Eneba_ON_HAC',name_sub)
      para_H_HADA%ComOp%Eneba_ON_HAC(:,1) = ZERO


      para_H_HADA%ComOp%file_HADA      = para_H%ComOp%file_HADA
      para_H_HADA%ComOp%calc_grid_HADA = para_H%ComOp%calc_grid_HADA

      nullify(para_H_HADA%ComOp%Rvp_spec)
      nullify(para_H_HADA%ComOp%Cvp_spec)
      nullify(para_H_HADA%ComOp%liste_spec)
      para_H_HADA%spectral         = .FALSE.
      para_H_HADA%ComOp%nb_vp_spec =  huge(1)
      para_H_HADA%spectral_Op      =  0

!     - copy parameters in para_H_HADA --------

      para_H_HADA%n_Op            = para_H%n_Op
      para_H_HADA%name_Op         = para_H%name_Op
      para_H_HADA%Make_Mat        = para_H%Make_Mat
      para_H_HADA%file_Grid       = para_H%file_Grid
      para_H_HADA%sym_Hamil       = para_H%sym_Hamil

      para_H_HADA%read_Op         = para_H%read_Op

      para_H_HADA%nb_bi         = 1
      para_H_HADA%nb_be         = 1
      para_H_HADA%nb_bie        = 1
      para_H_HADA%nb_ba         = para_H%nb_ba
      para_H_HADA%nb_qa         = para_H%nb_qa
      para_H_HADA%nb_bai        = para_H%nb_ba
      para_H_HADA%nb_qai        = para_H%nb_qa
      para_H_HADA%nb_baie       = para_H%nb_ba
      para_H_HADA%nb_bRot       = 1

      para_H_HADA%nb_tot        = para_H%nb_ba
      para_H_HADA%nb_tot_ini    = para_H%nb_ba
      para_H_HADA%nb_qaie       = para_H%nb_qa
      nullify(para_H_HADA%Rmat)
      nullify(para_H_HADA%Cmat)
      nullify(para_H_HADA%ind_Op)
      nullify(para_H_HADA%dim_Op)
      para_H_HADA%pack_Op         = para_H%pack_Op
      para_H_HADA%tol_pack        = para_H%tol_pack
      para_H_HADA%ratio_pack      = ZERO
      para_H_HADA%tol_nopack      = para_H%tol_nopack


      para_H_HADA%nb_act1       = para_H%nb_act1

      CALL alloc_array(para_H_HADA%OpGrid,(/para_H_HADA%nb_term/),      &
                      "para_H_HADA%OpGrid","param_HTOparam_H_HADA")
      CALL alloc_array(para_H_HADA%imOpGrid,(/1/),                      &
                      "para_H_HADA%imOpGrid","param_HTOparam_H_HADA")


      para_H_HADA%diago         = .FALSE.
      nullify(para_H_HADA%Cdiag)
      nullify(para_H_HADA%Rdiag)
      nullify(para_H_HADA%Cvp)
      nullify(para_H_HADA%Rvp)

      para_H_HADA%scaled          = .FALSE.
      para_H_HADA%E0              = ZERO
      para_H_HADA%Esc             = ONE
      para_H_HADA%Hmin            = huge(ONE)
      para_H_HADA%Hmax            = -huge(ONE)
      para_H_HADA%pot0            = para_H%pot0
      para_H_HADA%pot_only        = .FALSE.
      para_H_HADA%T_only          = .FALSE.





!-----------------------------------------------------------
      IF (debug) THEN
        CALL write_param_Op(para_H_HADA)
        write(out_unitp,*) ' END param_HTOparam_H_HADA'
      END IF
!-----------------------------------------------------------


      END SUBROUTINE param_HTOparam_H_HADA
!
!================================================================
! ++    Copy para_Op1 in para_Op2
!
!================================================================
!
      !!@description: TODO
      !!@param: TODO
      !!@param: TODO
      !!@param: TODO
      SUBROUTINE param_Op1TOparam_Op2(para_Op1,para_Op2)

!----- for the Operators -----------------------------------
      TYPE (param_Op)    :: para_Op1,para_Op2


      integer            :: i_bi
      integer            :: nb_ba,nb_bi,nb_be
      integer            :: nb_act1,nb_bie,nb_basis_act1
      integer            :: na(2)

      integer            :: k_term

!----- for debuging --------------------------------------------------
      logical,parameter :: debug=.FALSE.
!     logical,parameter :: debug=.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING param_Op1TOparam_Op2'
        CALL write_param_Op(para_Op1)
      END IF
!-----------------------------------------------------------

      para_Op2%init_var = .TRUE.
      para_Op2%alloc    = .FALSE.
      para_Op2%mat_done = .FALSE.

      IF (associated(para_Op1%para_AllBasis)) THEN
        para_Op2%para_AllBasis => para_Op1%para_AllBasis
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) '  CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%para_AllBasis',associated(para_Op1%para_AllBasis)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF
      IF (associated(para_Op1%BasisnD)) THEN
        para_Op2%BasisnD => para_Op1%BasisnD
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) '  CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%Basis2n',associated(para_Op1%Basis2n)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF
      IF (associated(para_Op1%Basis2n)) THEN
        para_Op2%Basis2n => para_Op1%Basis2n
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) '  CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%BasisnD',associated(para_Op1%BasisnD)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF
      para_Op2%symab = para_Op1%symab



      IF (associated(para_Op1%mole)) THEN
        para_Op2%mole      => para_Op1%mole
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) ' mole CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%mole',associated(para_Op1%mole)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF

      IF (associated(para_Op1%para_Tnum)) THEN
        para_Op2%para_Tnum => para_Op1%para_Tnum
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) ' para_Tnum CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%para_Tnum',associated(para_Op1%para_Tnum)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF


      IF (associated(para_Op1%para_PES)) THEN
        para_Op2%para_PES  => para_Op1%para_PES
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) ' para_PES CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%para_PES',associated(para_Op1%para_PES)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF


      IF (associated(para_Op1%ComOp)) THEN
        para_Op2%ComOp => para_Op1%ComOp
      ELSE
        write(out_unitp,*) ' ERROR in param_Op1TOparam_Op2'
        write(out_unitp,*) ' ComOp CANNOT be associated'
        write(out_unitp,*) ' asso para_Op1%ComOp',associated(para_Op1%ComOp)
        write(out_unitp,*) ' CHECK the source'
        STOP
      END IF

!     - copy parameters in para_Op2 --------
      para_Op2%spectral         =  para_Op1%spectral
      para_Op2%spectral_Op      =  para_Op1%spectral_Op


      para_Op2%n_Op            = para_Op1%n_Op
      para_Op2%name_Op         = para_Op1%name_Op
      para_Op2%Make_Mat        = para_Op1%Make_Mat
      para_Op2%para_ReadOp     = para_Op1%para_ReadOp
      para_Op2%file_Grid       = para_Op1%file_Grid
      para_Op2%read_Op         = para_Op1%read_Op
      para_Op2%cplx            = para_Op1%cplx
      para_Op2%nb_OpPsi        = 0
      para_Op2%sym_Hamil       = para_Op1%sym_Hamil

      para_Op2%nb_bi         = para_Op1%nb_bi
      para_Op2%nb_be         = para_Op1%nb_be
      para_Op2%nb_ba         = para_Op1%nb_ba
      para_Op2%nb_bie        = para_Op1%nb_bie
      para_Op2%nb_qa         = para_Op1%nb_qa
      para_Op2%nb_bai        = para_Op1%nb_bai
      para_Op2%nb_qai        = para_Op1%nb_qai
      para_Op2%nb_baie       = para_Op1%nb_baie
      para_Op2%nb_qaie       = para_Op1%nb_qaie
      para_Op2%nb_bRot       = para_Op1%nb_bRot

      para_Op2%nb_tot_ini    = para_Op1%nb_tot_ini
      IF (para_Op1%spectral) THEN
        para_Op2%nb_tot        = para_Op1%nb_tot_ini
      ELSE
        para_Op2%nb_tot        = para_Op1%nb_tot
      END IF
      nullify(para_Op2%Rmat)
      nullify(para_Op2%Cmat)
      nullify(para_Op2%ind_Op)
      nullify(para_Op2%dim_Op)
      para_Op2%pack_Op         = para_Op1%pack_Op
      para_Op2%tol_pack        = para_Op1%tol_pack
      para_Op2%ratio_pack      = ZERO
      para_Op2%tol_nopack      = para_Op1%tol_nopack


      para_Op2%diago         = .FALSE.
      nullify(para_Op2%Cdiag)
      nullify(para_Op2%Rdiag)
      nullify(para_Op2%Cvp)
      nullify(para_Op2%Rvp)


      para_Op2%nb_act1       = para_Op1%nb_act1

      para_Op2%nb_term       = para_Op1%nb_term
      para_Op2%nb_Term_Vib   = para_Op1%nb_Term_Vib
      para_Op2%nb_Term_Rot   = para_Op1%nb_Term_Rot


      nullify(para_Op2%OpGrid)
      nullify(para_Op2%imOpGrid)


      para_Op2%scaled          = .FALSE.
      para_Op2%E0              = ZERO
      para_Op2%Esc             = ONE
      para_Op2%Hmin            = huge(ONE)
      para_Op2%Hmax            = -huge(ONE)
      para_Op2%pot0            = para_Op1%pot0
      para_Op2%pot_only        = .FALSE.
      para_Op2%T_only          = .FALSE.


!-----------------------------------------------------------
      IF (debug) THEN
        CALL write_param_Op(para_Op2)
        write(out_unitp,*) ' END param_Op1TOparam_Op2'
      END IF
!-----------------------------------------------------------


      END SUBROUTINE param_Op1TOparam_Op2

      SUBROUTINE Set_File_OF_tab_Op(tab_Op,para_FileGrid)

      TYPE (param_Op), pointer, intent(inout) :: tab_Op(:)
      TYPE (param_FileGrid), optional         :: para_FileGrid

      integer :: iOp

      integer :: err_mem,memory
      character (len=*), parameter :: name_sub='Set_file_OF_AllOp'

      IF (.NOT. associated(tab_Op)) RETURN
      IF (size(tab_Op) < 1) RETURN

      IF (present(para_FileGrid)) THEN
        DO iOp=1,size(tab_Op)
          tab_Op(iOp)%para_ReadOp%para_fileGrid = para_fileGrid
        END DO
      ELSE
        DO iOp=1,size(tab_Op)
          tab_Op(iOp)%para_ReadOp%para_fileGrid = tab_Op(1)%para_ReadOp%para_fileGrid
        END DO
      END IF

      DO iOp=1,size(tab_Op)
        CALL Set_file_OF_OpGrid(tab_Op(iOp)%OpGrid,                     &
               tab_Op(iOp)%para_ReadOp%para_fileGrid%Type_FileGrid,iOp, &
               tab_Op(iOp)%para_ReadOp%para_fileGrid%Base_FileName_Grid,&
                           tab_Op(iOp)%name_Op,tab_Op(iOp)%nb_bie)

        CALL Set_file_OF_OpGrid(tab_Op(iOp)%ImOpGrid,                   &
               tab_Op(iOp)%para_ReadOp%para_fileGrid%Type_FileGrid,iOp, &
               tab_Op(iOp)%para_ReadOp%para_fileGrid%Base_FileName_Grid,&
                           tab_Op(iOp)%name_Op,tab_Op(iOp)%nb_bie)

      END DO

      END SUBROUTINE Set_File_OF_tab_Op
      SUBROUTINE Open_File_OF_tab_Op(tab_Op)

      TYPE (param_Op), pointer, intent(inout) :: tab_Op(:)

      integer :: iOp,nio

      integer :: err_mem,memory
      character (len=*), parameter :: name_sub='Open_File_OF_tab_Op'

      IF (.NOT. associated(tab_Op)) RETURN
      IF (size(tab_Op) < 1) RETURN

      DO iOp=1,size(tab_Op)
        CALL Open_file_OF_OpGrid(tab_Op(iOp)%OpGrid,nio)

        CALL Open_file_OF_OpGrid(tab_Op(iOp)%ImOpGrid,nio)

      END DO

      END SUBROUTINE Open_File_OF_tab_Op

      SUBROUTINE Close_File_OF_tab_Op(tab_Op)

      TYPE (param_Op), pointer, intent(inout) :: tab_Op(:)

      integer :: iOp,nio

      integer :: err_mem,memory
      character (len=*), parameter :: name_sub='Close_File_OF_tab_Op'

      IF (.NOT. associated(tab_Op)) RETURN
      IF (size(tab_Op) < 1) RETURN

      DO iOp=1,size(tab_Op)
        CALL Close_file_OF_OpGrid(tab_Op(iOp)%OpGrid)

        CALL Close_file_OF_OpGrid(tab_Op(iOp)%ImOpGrid)
      END DO

      END SUBROUTINE Close_File_OF_tab_Op


      SUBROUTINE read_OpGrid_OF_Op(para_Op)
      TYPE (param_Op), intent(inout) :: para_Op

      integer       :: i_qa
      integer       :: k_term
      integer       :: nio

      real (kind=Rkind) :: WnD
      real (kind=Rkind) :: Qact(para_Op%mole%nb_var)
      real (kind=Rkind) :: Qdyn(para_Op%mole%nb_var)

      TYPE (param_d0MatOp) :: d0MatOp
      integer              :: type_Op,iterm_Op,id1,id2

      character (len=*), parameter :: name_sub='read_OpGrid_OF_Op'

      IF (.NOT. para_Op%para_ReadOp%para_FileGrid%Save_FileGrid_done) RETURN
      IF (.NOT. para_Op%alloc_Grid)                                     &
                     CALL alloc_para_Op(para_Op,Grid=.TRUE.,Mat=.FALSE.)


      IF (para_Op%para_ReadOp%para_FileGrid%Type_FileGrid == 0) THEN

        type_Op = para_Op%type_Op
        IF (type_Op /= 1 .AND. type_Op /= 0) THEN
          write(out_unitp,*) ' ERROR in ',name_sub
          write(out_unitp,*) '    Type_HamilOp',type_Op
          write(out_unitp,*) '    Type_HamilOp MUST be equal to 1 for Type_FileGrid=0'
          write(out_unitp,*) '    CHECK your data!!'
          STOP
        END IF


        CALL Init_d0MatOp(d0MatOp,para_Op%param_TypeOp,para_Op%nb_bie)

        write(out_unitp,'(a)',ADVANCE='no') 'Read_HADA (%): 0'

        DO i_qa=1,para_Op%nb_qa

          CALL sub_reading_Op(i_qa,para_Op%nb_qa,d0MatOp,para_Op%n_Op,  &
                              Qdyn,para_Op%mole%nb_var,Qact,WnD,para_Op%ComOp)

          DO k_term=1,para_Op%nb_term

            id1 = para_Op%OpGrid(k_term)%derive_termQact(1)
            id2 = para_Op%OpGrid(k_term)%derive_termQact(2)
            iterm_Op = d0MatOp%derive_term_TO_iterm(id1,id2)

            para_Op%OpGrid(k_term)%Grid(i_qa,:,:) = d0MatOp%ReVal(:,:,iterm_Op)

          END DO

          IF (para_Op%cplx) THEN
            para_Op%imOpGrid(1)%Grid(i_qa,:,:) = d0MatOp%ImVal(:,:)
          END IF

          IF (mod(i_qa,max(1,int(para_Op%nb_qa/10))) == 0)                &
              write(out_unitp,'(a,i3)',ADVANCE='no') ' -',                &
                int(real(i_qa,kind=Rkind)*HUNDRED/real(para_Op%nb_qa,kind=Rkind))
           CALL flush_perso(out_unitp)

        END DO
        write(out_unitp,'(a)',ADVANCE='yes') ' - End'
        CALL flush_perso(out_unitp)
        CALL dealloc_d0MatOp(d0MatOp)
        !- loop OpGrid -------------------------------------
      ELSE
        DO k_term=1,para_Op%nb_term
          IF (para_Op%OpGrid(k_term)%grid_zero .AND. para_Op%OpGrid(k_term)%grid_cte) CYCLE

          !$OMP critical(CRIT_read_OpGrid_OF_Op)
          IF (para_Op%OpGrid(k_term)%file_Grid%seq) THEN   ! sequential acces file
            CALL sub_ReadSeq_Grid_iterm(para_Op%OpGrid(k_term)%Grid,para_Op%OpGrid(k_term))
          ELSE  ! direct acces file
            CALL sub_ReadDir_Grid_iterm(para_Op%OpGrid(k_term)%Grid,para_Op%OpGrid(k_term))
          END IF
          !$OMP end critical(CRIT_read_OpGrid_OF_Op)

        END DO
      END IF

      para_Op%para_ReadOp%para_FileGrid%Save_MemGrid_done  = .TRUE.

      CALL Analysis_OpGrid_OF_Op(para_Op)

      END SUBROUTINE read_OpGrid_OF_Op

!================================================================
!     Analysis of the grid (zero or constant terms)
!================================================================
      !!@description: TODO
      !!@param: TODO
      !!@param: TODO
      !!@param: TODO
      SUBROUTINE Analysis_OpGrid_OF_Op(para_Op)
      USE mod_MPI
      USE mod_param_SGType2
      TYPE (param_Op), intent(inout) :: para_Op

      integer          :: k_term,iq,iterm00
      real(kind=Rkind) :: Qact(para_Op%mole%nb_var)
      TYPE(OldParam)   :: OldPara

      character (len=*), parameter :: name_sub='Analysis_OpGrid_OF_Op'

       IF (.NOT. associated(para_Op%OpGrid)) THEN
         IF (print_level>-1 .AND. MPI_id==0) THEN
           write(out_unitp,*)'--------------------------------------------------------------'
           write(out_unitp,*)'n_Op,k_term,derive_term,cte,zero,    minval,    maxval,dealloc'
           write(out_unitp,'(i5,1x,a)') para_Op%n_Op,'This Operator is not allocated'
           write(out_unitp,*)'--------------------------------------------------------------'
         END IF
         RETURN
       END IF


       CALL Analysis_OpGrid(para_Op%OpGrid,para_Op%n_Op)

       IF (print_level>-1) THEN
         iterm00 = para_Op%derive_term_TO_iterm(0,0)
         iq = para_Op%OpGrid(iterm00)%iq_min
         IF (iq > 0) THEN
           CALL Rec_Qact(Qact,para_Op%para_AllBasis%BasisnD,iq,para_Op%mole,OldPara)
           IF(MPI_id==0) write(out_unitp,*) 'iq_min,Op_min,Qact',iq,para_Op%OpGrid(iterm00)%Op_min,Qact(1:para_Op%mole%nb_act1)
         END IF
         iq = para_Op%OpGrid(iterm00)%iq_max
         IF (iq > 0) THEN
           CALL Rec_Qact(Qact,para_Op%para_AllBasis%BasisnD,iq,para_Op%mole,OldPara)
           IF(MPI_id==0) write(out_unitp,*) 'iq_max,Op_max,Qact',iq,para_Op%OpGrid(iterm00)%Op_max,Qact(1:para_Op%mole%nb_act1)
         END IF
       END IF

       IF (print_level>-1 .AND. MPI_id==0) write(out_unitp,*) 'Analysis of the imaginary Op grid',para_Op%cplx
       IF (para_Op%cplx) THEN
         CALL Analysis_OpGrid(para_Op%imOpGrid,para_Op%n_Op)
       END IF

       CALL dealloc_OldParam(OldPara)
    END SUBROUTINE Analysis_OpGrid_OF_Op

!=======================================================================================
!     initialization of psi
!=======================================================================================
      SUBROUTINE init_psi(psi,para_H,cplx)
      USE mod_system
      USE mod_psi_set_alloc
      !USE mod_psi
      IMPLICIT NONE

!----- variables for the WP propagation ----------------------------
      TYPE (param_psi), intent(inout)   :: psi
      logical,          intent(in)      :: cplx

!----- Operator to link BasisnD, Basis2n, ComOp ---------------------
      TYPE (param_Op),  intent(in)      :: para_H

!----- for debuging --------------------------------------------------
       !logical, parameter :: debug = .TRUE.
       logical, parameter :: debug = .FALSE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING init_psi : cplx',cplx
      END IF
!-----------------------------------------------------------
!----- link the basis set ---------------------------------
     IF (associated(para_H%para_AllBasis%BasisnD)) THEN
       psi%BasisnD => para_H%para_AllBasis%BasisnD
     ELSE
       write(out_unitp,*) ' ERROR in init_psi'
       write(out_unitp,*) ' BasisnD CANNOT be associated'
       write(out_unitp,*) ' asso para_H%...%BasisnD',associated(para_H%para_AllBasis%BasisnD)
       write(out_unitp,*) ' CHECK the source'
       STOP
     END IF
     IF (associated(para_H%para_AllBasis%Basis2n)) THEN
       psi%Basis2n => para_H%para_AllBasis%Basis2n
     ELSE
       write(out_unitp,*) ' ERROR in init_psi'
       write(out_unitp,*) ' Basis2n CANNOT be associated'
       write(out_unitp,*) ' asso para_H%...%Basis2n',associated(para_H%para_AllBasis%Basis2n)
       write(out_unitp,*) ' CHECK the source'
       STOP
     END IF
!-----------------------------------------------------------


!----- link ComOp -----------------------------------------
      IF (associated(para_H%ComOp)) THEN
          psi%ComOp     => para_H%ComOp
      ELSE
         write(out_unitp,*) ' ERROR in init_psi'
         write(out_unitp,*) ' ComOp CANNOT be associated'
         write(out_unitp,*) ' asso para_H%ComOp',associated(para_H%ComOp)
         write(out_unitp,*) ' CHECK the source'
         STOP
      END IF
!-----------------------------------------------------------

      psi%init         = .TRUE.
      psi%cplx         = cplx

      psi%nb_tot       = para_H%nb_tot
      psi%nb_baie      = para_H%nb_baie
      psi%nb_ba        = para_H%nb_ba
      psi%nb_bi        = para_H%nb_bi
      psi%nb_be        = para_H%nb_be
      psi%nb_bRot      = para_H%nb_bRot

      psi%nb_qa        = para_H%nb_qa
      psi%nb_qaie      = para_H%nb_qaie


      psi%nb_act1      = para_H%mole%nb_act1
      psi%nb_act       = para_H%mole%nb_act

      psi%nb_basis_act1= max(1,psi%BasisnD%nb_basis)
      psi%nb_basis     = psi%nb_basis_act1 + psi%Basis2n%nb_basis
      psi%max_dim      = maxval( psi%BasisnD%nDindB%nDsize(:) )


      IF (debug) THEN
        CALL ecri_init_psi(psi)
        write(out_unitp,*) 'END init_psi'
      END IF
      END SUBROUTINE init_psi
!=======================================================================================

END MODULE mod_SetOp

