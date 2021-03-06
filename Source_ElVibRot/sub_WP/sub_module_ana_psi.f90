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
MODULE mod_ana_psi
  USE mod_system
  USE mod_nDindex
  USE mod_Constant
  IMPLICIT NONE

  PRIVATE
  PUBLIC :: sub_analyze_tab_psi,sub_analyze_psi,Channel_weight
  PUBLIC :: norm2_psi,renorm_psi_With_norm2,renorm_psi
#if(run_MPI)
  PUBLIC :: norm_psi_MPI
#endif

CONTAINS

!================================================================
!
!     sub_analyze_psi :
!       ....
!       Rho1D, Rho2D
!
!================================================================
SUBROUTINE sub_analyze_tab_Psi(tab_psi,ana_psi,adia)
  USE mod_system
  USE mod_psi_set_alloc
  IMPLICIT NONE

  TYPE (param_psi),     intent(inout)        :: tab_psi(:)
  TYPE (param_ana_psi), intent(inout)        :: ana_psi
  logical,              intent(in)           :: adia


!-- working parameters --------------------------------
  integer           :: i

!- for debuging --------------------------------------------------
  character (len=*), parameter :: name_sub='sub_analyze_tab_Psi'
  logical, parameter :: debug=.FALSE.
! logical, parameter :: debug=.TRUE.
!-------------------------------------------------------
  IF (debug) THEN
    write(out_unitp,*) 'BEGINNING ',name_sub
    write(out_unitp,*)
    CALL flush_perso(out_unitp)
   END IF
!-------------------------------------------------------

  DO i=1,size(tab_psi)
    ana_psi%num_psi = i
    ana_psi%Ene     = real(tab_psi(i)%CAvOp,kind=Rkind)
    CALL sub_analyze_psi(tab_psi(i),ana_psi,adia=adia)
  END DO


!----------------------------------------------------------
  IF (debug) THEN
    write(out_unitp,*) 'END ',name_sub
    CALL flush_perso(out_unitp)
  END IF
!----------------------------------------------------------
END SUBROUTINE sub_analyze_tab_Psi

SUBROUTINE sub_analyze_psi(psi,ana_psi,adia)
  USE mod_system
  USE mod_psi_set_alloc
  IMPLICIT NONE

  !----- variables for the WP -------------------------------
  TYPE (param_psi),     intent(inout)         :: psi
  TYPE (param_ana_psi), intent(inout)         :: ana_psi
  logical,              intent(in)            :: adia


  integer                           :: i,j,i_be,i_bi
  real (kind=Rkind)                 :: pop,Etemp
  character(len=:), allocatable     :: lformat
  TYPE(REAL_WU)                     :: RWU_Temp,RWU_E,RWU_DE
  real (kind=Rkind)                 :: E,DE

  real (kind=Rkind), allocatable    :: tab_WeightChannels(:,:)
  integer                           :: Dominant_Channel(2)
  real (kind=Rkind)                 :: w,Psi_norm2

  character(len=:), allocatable     :: info
  character(len=:), allocatable     :: psi_line

  integer                           :: nioPsi
  character (len=Line_len)          :: name_filePsi      = " "     ! name of the file

  !----- dynamic allocation memory ------------------------------------
  real (kind=Rkind), allocatable :: moy_Qba(:)
  real (kind=Rkind), allocatable :: Mij(:,:,:)
!----- for debuging --------------------------------------------------
  character (len=*), parameter :: name_sub='sub_analyze_psi'
  integer :: err_mem,memory
  logical, parameter :: debug=.FALSE.
  !logical, parameter :: debug=.TRUE.
!-----------------------------------------------------------

  IF (debug) THEN
    write(out_unitp,*) 'BEGINNING ',name_sub
    CALL flush_perso(out_unitp)
  END IF

  IF (psi%ComOp%contrac_ba_ON_HAC) THEN
    ana_psi%AvQ = .FALSE.
  END IF

  !----------------------------------------------------------------------
  ! Boltzmann population
  IF (ana_psi%Boltzmann_pop) THEN

    RWU_Temp = REAL_WU(ana_psi%Temp,'°K','E')
    !Etemp   = RWU_Temp  ! Temperature convertion in Hartree
    Etemp    = convRWU_TO_R(RWU_Temp ,WorkingUnit=.TRUE.)

    pop = exp(-(ana_psi%Ene-ana_psi%ZPE)/Etemp) / ana_psi%Part_func
  END IF


  !----------------------------------------------------------------------
  ! tab_WeightChannels
  IF (ana_psi%propa) THEN

    RWU_E  = REAL_WU(ana_psi%Ene,'au','E')
    E      = convRWU_TO_R(RWU_E ,WorkingUnit=.FALSE.)

    IF (adia) THEN
      CALL Channel_weight(tab_WeightChannels,psi,                       &
                                        GridRep=.TRUE.,BasisRep=.FALSE.)
      info = '#WPadia ' // int_TO_char(ana_psi%num_psi)
    ELSE
      CALL Channel_weight(tab_WeightChannels,psi,                       &
                                        GridRep=.FALSE.,BasisRep=.TRUE.)
      info = '#WP ' // int_TO_char(ana_psi%num_psi)
    END IF
    Psi_norm2 = sum(tab_WeightChannels)

    ! add the psi number + the time
    psi_line = 'norm^2-WP ' // info // ' ' // real_TO_char(ana_psi%T,Rformat='f12.2')

    ! add the energy
    psi_line = psi_line // ' ' // real_TO_char(E,Rformat='f8.5')

    ! add the field (if necessary)
    IF (ana_psi%With_field) THEN
      psi_line = psi_line // ' ' // real_TO_char(ana_psi%field(1),Rformat='f8.5')
      psi_line = psi_line // ' ' // real_TO_char(ana_psi%field(2),Rformat='f8.5')
      psi_line = psi_line // ' ' // real_TO_char(ana_psi%field(3),Rformat='f8.5')
    END IF

    psi_line = psi_line // ' ' // real_TO_char(Psi_norm2,Rformat='f10.7')
    DO i_be=1,psi%nb_be
    DO i_bi=1,psi%nb_bi
      w = tab_WeightChannels(i_bi,i_be)
      psi_line = psi_line // ' ' // real_TO_char(w,Rformat='f10.7')
    END DO
    END DO

    write(out_unitp,*) psi_line

    IF (ana_psi%Coherence > 0) THEN
      CALL alloc_NParray(Mij,(/ 2, psi%nb_bi*psi%nb_be, psi%nb_bi*psi%nb_be/),'Mij',name_sub)

      CALL sub_Rhoi_Rhoj_Over_Rho(psi,Mij,ana_psi)

      psi_line = 'Mij ' // info // ' ' // real_TO_char(ana_psi%T,Rformat='f12.2')

      DO i=1,size(Mij(1,:,1))
      DO j=i+1,size(Mij(1,:,1))

        write(out_unitp,*) 'M-' // int_TO_char(i) // '-' //             &
                           int_TO_char(j) // ' ' // info // ' ' //      &
                    real_TO_char(ana_psi%T,Rformat='f12.2') // ': ' //  &
                    real_TO_char(Mij(1,i,j),Rformat='f12.8'),' ',       &
                    real_TO_char(Mij(2,i,j),Rformat='f12.8')

      END DO
      END DO
      CALL dealloc_NParray(Mij,'Mij',name_sub)
    END IF

  ELSE ! not propa
    CALL Channel_weight(tab_WeightChannels,psi,                         &
                        GridRep=.FALSE.,BasisRep=.TRUE.,                &
                        Dominant_Channel=Dominant_Channel)

    RWU_E  = REAL_WU(ana_psi%Ene,'au','E')
    RWU_DE = REAL_WU(ana_psi%Ene-ana_psi%ZPE,'au','E')
    E      = convRWU_TO_R(RWU_E ,WorkingUnit=.FALSE.)
    DE     = convRWU_TO_R(RWU_DE,WorkingUnit=.FALSE.)

    IF (ana_psi%AvQ) THEN
      CALL alloc_NParray(moy_Qba,(/2*Psi%BasisnD%ndim/),"moy_Qba",name_sub)
      CALL sub_Qmoy(psi,moy_Qba,ana_psi)

      IF (ana_psi%num_psi < 10000 .AND. Dominant_Channel(2) < 10000) THEN
        lformat = String_TO_String('("lev: ",i4,i4,l3,' //              &
                                   int_TO_char(3+size(moy_Qba)) //      &
                       "(1x," // trim(adjustl(EneIO_format)) // "))")
      ELSE
        lformat = String_TO_String('("lev: ",i0,i0,l3,' //              &
                                   int_TO_char(3+size(moy_Qba)) //      &
                       "(1x," // trim(adjustl(EneIO_format)) // "))")
      END IF

      write(out_unitp,lformat) ana_psi%num_psi,Dominant_Channel(2),psi%convAvOp,  &
                               E,DE,pop,moy_Qba(:)

      CALL dealloc_NParray(moy_Qba,"moy_Qba",name_sub)
    ELSE

      IF (ana_psi%num_psi < 10000 .AND. Dominant_Channel(2) < 10000) THEN
        lformat = String_TO_String( '("lev: ",i4,i4,l3,3(1x,' //      &
                               trim(adjustl(EneIO_format)) // '))' )
      ELSE
        lformat = String_TO_String( '("lev: ",i0,i0,l3,3(1x,' //      &
                               trim(adjustl(EneIO_format)) // '))' )
      END IF

      write(out_unitp,lformat) ana_psi%num_psi,Dominant_Channel(2),psi%convAvOp,E,DE,pop
    END IF

    info = String_TO_String( " " // real_TO_char(E,"f12.6" ) // " : ")
  END IF
  !----------------------------------------------------------------------

  !----------------------------------------------------------------------
  CALL flush_perso(out_unitp)

  IF (psi%nb_bi > 1 .AND. .NOT. ana_psi%propa) THEN

    lformat = String_TO_String( '("% HAC: ",' //                    &
                            int_TO_char(psi%nb_bi) // "(1x,f4.0) )" )

    write(out_unitp,lformat) (tab_WeightChannels(i_bi,1)*TEN**2,i_bi=1,psi%nb_bi)
  END IF

  CALL calc_1Dweight(psi,ana_psi,tab_WeightChannels,20,real(ana_psi%num_psi,kind=Rkind),info,.TRUE.)

  IF (.NOT. adia .AND. .NOT. ana_psi%propa) CALL calc_MaxCoef_psi(psi,ana_psi%T,info)

  IF (ana_psi%propa) CALL psi_Qba_ie_psi(ana_psi%T,psi,ana_psi,tab_WeightChannels,info)

  CALL Rho1D_Rho2D_psi(psi,ana_psi)

  CALL write1D2D_psi(psi,ana_psi)

  !---------------------------------------------------------------------------
  IF (ana_psi%Write_psi) THEN
    ! write one the grid
    IF (ana_psi%Write_psi2_Grid) THEN
      name_filePsi = ana_psi%file_Psi%name
      IF (adia) THEN
        name_filePsi = trim(name_filePsi) // '_GridAdiaPsi2'
      ELSE
        name_filePsi = trim(name_filePsi) // '_GridPsi2'
      END IF

      IF (ana_psi%propa) name_filePsi = trim(name_filePsi) // '-' // int_TO_char(ana_psi%num_psi)

      IF (ana_psi%propa .AND. ana_psi%T == ZERO) THEN
        CALL file_open2(name_filePsi,nioPsi)
      ELSE
        CALL file_open2(name_filePsi,nioPsi,append=.TRUE.)
      END IF

      CALL ecri_psi(T=ana_psi%T,psi=psi,nioWP=nioPsi,                   &
                    ecri_GridRep=.TRUE.,ecri_BasisRep=.FALSE.,          &
                    ecri_psi2=.TRUE.)
      close(nioPsi)
    END IF

    IF (.NOT. adia .AND. ana_psi%Write_psi_Grid) THEN
      name_filePsi = trim(ana_psi%file_Psi%name) // '_GridPsi'
      IF (ana_psi%propa) name_filePsi = trim(name_filePsi) // '-' // int_TO_char(ana_psi%num_psi)

      IF (ana_psi%propa .AND. ana_psi%T == ZERO) THEN
        CALL file_open2(name_filePsi,nioPsi)
      ELSE
        CALL file_open2(name_filePsi,nioPsi,append=.TRUE.)
      END IF

      CALL ecri_psi(T=ana_psi%T,psi=psi,nioWP=nioPsi,                   &
                    ecri_GridRep=.TRUE.,ecri_BasisRep=.FALSE.,          &
                    ecri_psi2=.FALSE.)
      close(nioPsi)
    END IF
    !---------------------------------------------------------------------------

    IF (.NOT. adia .AND. ana_psi%Write_psi2_Basis) THEN
      name_filePsi = trim(ana_psi%file_Psi%name) // '_BasisPsi2'
      IF (ana_psi%propa) name_filePsi = trim(name_filePsi) // '-' // int_TO_char(ana_psi%num_psi)

      IF (ana_psi%propa) THEN
        IF (ana_psi%T == ZERO) THEN
          CALL file_open2(name_filePsi,nioPsi)
        ELSE
          CALL file_open2(name_filePsi,nioPsi,append=.TRUE.)
        END IF
        CALL ecri_psi(T=ana_psi%T,psi=psi,nioWP=nioPsi,            &
                      ecri_GridRep=.FALSE.,ecri_BasisRep=.TRUE.,   &
                      ecri_psi2=.FALSE.)
      ELSE
        IF (ana_psi%num_psi == 1) THEN
          CALL file_open2(name_filePsi,nioPsi)
        ELSE
          CALL file_open2(name_filePsi,nioPsi,append=.TRUE.)
        END IF
        CALL ecri_psi(psi=psi,nioWP=nioPsi,                        &
                      ecri_GridRep=.FALSE.,ecri_BasisRep=.TRUE.,   &
                      ecri_psi2=.FALSE.)
      END IF

    END IF

    IF (.NOT. adia .AND. ana_psi%Write_psi_Basis) THEN
      name_filePsi = trim(ana_psi%file_Psi%name) // '_BasisPsi'
      IF (ana_psi%propa) name_filePsi = trim(name_filePsi) // '-' // int_TO_char(ana_psi%num_psi)

      IF (ana_psi%propa) THEN
        IF (ana_psi%T == ZERO) THEN
          CALL file_open2(name_filePsi,nioPsi)
        ELSE
          CALL file_open2(name_filePsi,nioPsi,append=.TRUE.)
        END IF
        CALL ecri_psi(T=ana_psi%T,psi=psi,nioWP=nioPsi,            &
                      ecri_GridRep=.FALSE.,ecri_BasisRep=.TRUE.,   &
                      ecri_psi2=.FALSE.)
      ELSE
        IF (ana_psi%num_psi == 1) THEN
          CALL file_open2(name_filePsi,nioPsi)
        ELSE
          CALL file_open2(name_filePsi,nioPsi,append=.TRUE.)
        END IF
        CALL ecri_psi(psi=psi,nioWP=nioPsi,                        &
                      ecri_GridRep=.FALSE.,ecri_BasisRep=.TRUE.,   &
                      ecri_psi2=.FALSE.)
      END IF

    END IF
  END IF

!         CALL calc_DM(WP(i),max_ecri,T,info,.TRUE.)
!         C12 = WP(i)%CvecB(1)*conjg(WP(i)%CvecB(2))
!         write(out_unitp,31) T,i,C12,abs(C12)
!31       format('C12',f12.1,1x,i2,3(1x,f12.6))
          !CALL calc_nDTk(WP(i),T)

  IF (allocated(tab_WeightChannels)) THEN
    CALL dealloc_NParray(tab_WeightChannels,                    &
                        "tab_WeightChannels",name_sub)
  END IF
  IF (allocated(info))     deallocate(info)
  IF (allocated(psi_line)) deallocate(psi_line)
  IF (allocated(lformat))  deallocate(lformat)
  IF (allocated(moy_Qba))  deallocate(moy_Qba)

  IF (debug) THEN
    write(out_unitp,*) 'END ',name_sub
  END IF
  CALL flush_perso(out_unitp)

END SUBROUTINE sub_analyze_psi
!================================================================
!
!     calculation of <psi | Qact(j) | psi>
!
!================================================================
      SUBROUTINE sub_Qmoy(Psi,moy_Qba,ana_psi)
      USE mod_system
      USE mod_dnSVM
      USE mod_psi_set_alloc
      USE mod_psi_B_TO_G
      IMPLICIT NONE

      TYPE (param_psi)   :: Psi
      TYPE (param_ana_psi), intent(inout) :: ana_psi

!------ means value ---------------------------------------
      real (kind=Rkind)  ::    moy_Qba(2*Psi%nb_act1)


!------ working variables ---------------------------------
      integer           :: i,i_q,i_ie,iqie,dnErr
      real (kind=Rkind) :: psi2,WrhonD
      real (kind=Rkind) :: x(Psi%BasisnD%ndim)
      TYPE (Type_dnS)   :: dnt
      real (kind=Rkind) :: cte(20)

!----- for debuging --------------------------------------------------
      logical, parameter :: debug =.FALSE.
      !logical, parameter :: debug =.TRUE.
      !-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING sub_Qmoy'
        CALL flush_perso(out_unitp)
      END IF
!-----------------------------------------------------------

      cte(:) = ZERO
      IF (allocated(ana_psi%Qtransfo_type)) CALL alloc_dnSVM(dnt,1,3)

      IF (.NOT. ana_psi%GridDone) CALL sub_PsiBasisRep_TO_GridRep(Psi)

      moy_Qba(:)  = ZERO

      DO i_q=1,Psi%nb_qa
        psi2 = ZERO
        DO i_ie=1,Psi%nb_bi*Psi%nb_be

          iqie = (i_ie-1)*Psi%nb_qa + i_q

          IF (Psi%cplx) THEN
            psi2 = psi2 + abs(Psi%CvecG(iqie))**2
          ELSE
            psi2 = psi2 + abs(Psi%RvecG(iqie))**2
          END IF
        END DO

        !- calculation of x -------------------------------
        CALL Rec_x(x,psi%BasisnD,i_q)

        IF (allocated(ana_psi%Qtransfo_type)) THEN
          DO i=1,size(x)
            CALL sub_dntf(ana_psi%Qtransfo_type(i),dnt,x(i),cte,dnErr)
            IF (dnErr /= 0) THEN
              write(out_unitp,*) ' ERROR in sub_Qmoy'
              write(out_unitp,*) '   ERROR in the sub_dntf call for the coordinates, iQdyn:',psi%BasisnD%iQdyn(i)
              STOP 'ERROR in sub_dntf called from sub_Qmoy'
            END IF
            x(i) = dnt%d0
          END DO
        END IF
        !write(out_unitp,*) 'x',x

        !- calculation of WrhonD ------------------------------
        WrhonD = Rec_WrhonD(Psi%BasisnD,i_q)
        ! write(out_unitp,*) i,'WrhonD',WrhonD

        psi2 = psi2 * WrhonD

        moy_Qba(1:Psi%nb_act1) = moy_Qba(1:Psi%nb_act1) + psi2 * x(:)
        moy_Qba(1+Psi%nb_act1:2*Psi%nb_act1) =                         &
                  moy_Qba(1+Psi%nb_act1:2*Psi%nb_act1) + psi2 * x(:)**2
      END DO

      moy_Qba(1+Psi%nb_act1:2*Psi%nb_act1) =                           &
                                moy_Qba(1+Psi%nb_act1:2*Psi%nb_act1) - &
                                              moy_Qba(1:Psi%nb_act1)**2

      IF (allocated(ana_psi%Qtransfo_type)) CALL dealloc_dnSVM(dnt)

!----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END sub_Qmoy'
      END IF
!----------------------------------------------------------

      END SUBROUTINE sub_Qmoy

      SUBROUTINE sub_Rhoi_Rhoj_Over_Rho(Psi,Mij,ana_psi)
      USE mod_system
      USE mod_psi_set_alloc
      USE mod_psi_B_TO_G
      IMPLICIT NONE

      TYPE (param_psi)    , intent(inout) :: Psi
      TYPE (param_ana_psi), intent(inout) :: ana_psi

!------ value ---------------------------------------
      real (kind=Rkind)  :: Mij(2,Psi%nb_bi*Psi%nb_be,Psi%nb_bi*Psi%nb_be)


!------ working variables ---------------------------------
      integer            :: i,j,i_q,i_ie,j_ie,iqie
      real (kind=Rkind)  :: x,Rho,Rho_i(Psi%nb_bi*Psi%nb_be)

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub = 'sub_Rhoi_Rhoj_Over_Rho'
      logical, parameter :: debug =.FALSE.
      !logical, parameter :: debug =.TRUE.
      !-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        CALL flush_perso(out_unitp)
      END IF
!-----------------------------------------------------------

      IF (.NOT. ana_psi%GridDone) CALL sub_PsiBasisRep_TO_GridRep(Psi)

      Mij(:,:,:)  = ZERO

      DO i_q=1,Psi%nb_qa
        Rho_i(:) = ZERO
        DO i_ie=1,Psi%nb_bi*Psi%nb_be

          iqie = (i_ie-1)*Psi%nb_qa + i_q

          IF (Psi%cplx) THEN
            Rho_i(i_ie) = Rho_i(i_ie) + abs(Psi%CvecG(iqie))**2
          ELSE
            Rho_i(i_ie) = Rho_i(i_ie) + abs(Psi%RvecG(iqie))**2
          END IF
        END DO


        !- calculation of total density, Rho ----------------------------
        Rho = sum(Rho_i)

        x =  Rec_WrhonD(Psi%BasisnD,i_q)

        DO i_ie=1,Psi%nb_bi*Psi%nb_be
        DO j_ie=1,Psi%nb_bi*Psi%nb_be

          IF (Rho > ana_psi%coherence_epsi)                             &
             Mij(1,i_ie,j_ie) = Mij(1,i_ie,j_ie) + Rho_i(i_ie)*Rho_i(j_ie) * x/Rho

          Mij(2,i_ie,j_ie) = Mij(2,i_ie,j_ie) + Rho_i(i_ie)*Rho_i(j_ie) * x

        END DO
        END DO


      END DO


!----------------------------------------------------------
      IF (debug) THEN

        DO i_ie=1,Psi%nb_bi*Psi%nb_be
        DO j_ie=i_ie+1,Psi%nb_bi*Psi%nb_be

         write(out_unitp,*) 'Mij ',i_ie,j_ie,Mij(:,i_ie,j_ie)

        END DO
        END DO

        write(out_unitp,*) 'END ',name_sub
      END IF
!----------------------------------------------------------

      END SUBROUTINE sub_Rhoi_Rhoj_Over_Rho

!================================================================
!
!     means of Qact1(i) psi  : <psi|Qact(i)|psi>
!
!================================================================
      SUBROUTINE psi_Qba_ie_psi(T,psi,ana_psi,tab_WeightChannels,info)
      USE mod_system
      USE mod_param_SGType2
      USE mod_psi_set_alloc
      USE mod_psi_B_TO_G
      IMPLICIT NONE

!----- variables for the WP ----------------------------------------
      TYPE (param_psi),     intent(inout)           :: psi
      TYPE (param_ana_psi), intent(in)              :: ana_psi
      character (len=*),    intent(in)              :: info
      real (kind=Rkind),    intent(in)              :: T
      real (kind=Rkind),    intent(in), allocatable :: tab_WeightChannels(:,:)


!------ working variables ---------------------------------
      TYPE(OldParam)    :: OldPara
      real (kind=Rkind) :: Qmean(psi%nb_act1)
      real (kind=Rkind) :: Qmean_ie(psi%nb_act1,psi%nb_bi,psi%nb_be)
      real (kind=Rkind) :: x(Psi%BasisnD%ndim)
      integer           :: i_qa,i_qaie
      integer           :: i_be,i_bi,i_ba,i_baie
      integer           :: ii_baie,if_baie
      integer           :: i
      real (kind=Rkind) :: WrhonD,temp
      logical           :: psiN,norm2GridRep,norm2BasisRep

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub = 'psi_Qba_ie_psi'
      logical,parameter :: debug = .FALSE.
      !logical,parameter :: debug = .TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'psi'
        CALL ecri_psi(Psi=psi)
      END IF
!-----------------------------------------------------------

      IF (psi%nb_baie > psi%nb_tot) RETURN


      IF (.NOT. allocated(tab_WeightChannels)) THEN
        write(out_unitp,*) 'ERROR in ',name_sub
        write(out_unitp,*) 'tab_WeightChannels is not allocated!!'
        write(out_unitp,*) ' It should be done in sub_analyze or sub_analyze_WP_forPropa'
        STOP
      END IF

      Qmean(:)        = ZERO
      Qmean_ie(:,:,:) = ZERO

      IF (.NOT. ana_psi%GridDone) CALL sub_PsiBasisRep_TO_GridRep(psi)


      DO i_qa=1,psi%nb_qa

        !- calculation of WrhonD ------------------------------
        WrhonD = Rec_WrhonD(psi%BasisnD,i_qa,OldPara)

        !- calculation of x -------------------------------
        CALL Rec_x(x,psi%BasisnD,i_qa,OldPara)

        DO i_be=1,psi%nb_be
        DO i_bi=1,psi%nb_bi
          i_qaie = i_qa + ( (i_bi-1)+(i_be-1)*psi%nb_bi ) * psi%nb_qa

          IF (psi%cplx) THEN
            temp = abs( psi%CvecG(i_qaie) )
          ELSE
            temp = psi%RvecG(i_qaie)
          END IF
          temp = WrhonD * temp**2

          Qmean(:) = Qmean(:) + x(:) * temp
          Qmean_ie(:,i_bi,i_be) = Qmean_ie(:,i_bi,i_be) + x(:) * temp

        END DO
        END DO

      END DO

      Qmean(:) = Qmean(:) / sum(tab_WeightChannels)


      DO i_be=1,psi%nb_be
      DO i_bi=1,psi%nb_bi
        IF (tab_WeightChannels(i_bi,i_be) > ONETENTH**7) THEN
          Qmean_ie(:,i_bi,i_be) = Qmean_ie(:,i_bi,i_be) /               &
                                  tab_WeightChannels(i_bi,i_be)
        ELSE
          Qmean_ie(:,i_bi,i_be) = ZERO
        END IF
      END DO
      END DO

      DO i=1,psi%nb_act1
          write(out_unitp,11) 'T iQbasis Qmean_ie ',info,T,i,Qmean_ie(i,:,:)
          write(out_unitp,11) 'T iQbasis Qmean    ',info,T,i,Qmean(i)
      END DO
 11   format(2a,' ',f12.4,' ',i4,' ',100(' ',f6.3))
      CALL flush_perso(out_unitp)

      CALL dealloc_OldParam(OldPara)

!----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'Qmean',Qmean
        DO i=1,psi%nb_act1
          write(out_unitp,*) 'Qmean_ie',i,Qmean_ie(i,:,:)
        END DO
        write(out_unitp,*) 'END ',name_sub
      END IF
!----------------------------------------------------------


      END SUBROUTINE psi_Qba_ie_psi
      SUBROUTINE write1D2D_psi(psi,ana_psi)
      USE mod_system
      USE mod_dnSVM
      USE mod_psi_set_alloc
      USE mod_psi_B_TO_G
      IMPLICIT NONE

!----- variables for the WP ----------------------------------------
      TYPE (param_psi),     intent(inout)  :: psi
      TYPE (param_ana_psi), intent(inout)  :: ana_psi



!----- working variables ------------------------------------------
      real (kind=Rkind) :: val,val_mini,val_psi2,val_Rpsi,val_Cpsi

      integer           :: i_qa,i_qaie,iq,jq
      integer           :: ib,jb,i_bie


      TYPE (Type_dnVec) :: Tab1D_Qact(psi%BasisnD%nb_basis)
      TYPE (Type_dnVec) :: Tab1D_psi2(psi%BasisnD%nb_basis)
      TYPE (Type_dnVec) :: Tab1D_Rpsi(psi%BasisnD%nb_basis)
      TYPE (Type_dnVec) :: Tab1D_Cpsi(psi%BasisnD%nb_basis)

      TYPE (Type_dnMat) :: Tab2D_psi2(psi%BasisnD%nb_basis,psi%BasisnD%nb_basis)
      TYPE (Type_dnMat) :: Tab2D_Rpsi(psi%BasisnD%nb_basis,psi%BasisnD%nb_basis)
      TYPE (Type_dnMat) :: Tab2D_Cpsi(psi%BasisnD%nb_basis,psi%BasisnD%nb_basis)

      integer :: nDval0(psi%BasisnD%nb_basis)
      integer :: nDval(psi%BasisnD%nb_basis)
      integer :: nDvalib(psi%BasisnD%nb_basis)
      integer :: nDval0ib(psi%BasisnD%nb_basis)

!------ working variables ---------------------------------
      TYPE (param_file)              :: file_psi
      integer                        :: nio,nqi,nqj

      character (len=:), allocatable  :: state_name

!----- for debuging --------------------------------------------------
      integer :: err_mem,memory
      character (len=*), parameter :: name_sub='write1D2D_psi'
      logical,parameter :: debug = .FALSE.
      !logical,parameter :: debug = .TRUE.
!-----------------------------------------------------------

      IF (.NOT.ana_psi%psi1D_Q0 .AND. .NOT.ana_psi%psi2D_Q0) RETURN
      IF (ana_psi%adia) RETURN

      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*)
      END IF
!-----------------------------------------------------------

      IF (psi%nb_act1 /= psi%BasisnD%nb_basis) THEN
        write(out_unitp,*) 'WARNNING in',name_sub
        write(out_unitp,*) 'nb_act1 /= BasisnD%nb_basis',psi%nb_act1,psi%BasisnD%nb_basis
        RETURN
      END IF


      IF (.NOT. ana_psi%GridDone) CALL sub_PsiBasisRep_TO_GridRep(psi)

      nDval0(:) = 0
      DO ib=1,psi%BasisnD%nb_basis
        nqi = get_nq_FROM_basis(psi%BasisnD%tab_Pbasis(ib)%Pbasis)

        CALL alloc_dnVec(Tab1D_Qact(ib),nqi)
        CALL alloc_dnVec(Tab1D_psi2(ib),nqi)
        CALL alloc_dnVec(Tab1D_Rpsi(ib),nqi)
        CALL alloc_dnVec(Tab1D_Cpsi(ib),nqi)

        Tab1D_Qact(ib)%d0(:) = psi%BasisnD%tab_Pbasis(ib)%Pbasis%x(1,:)

        ! set the table nDval0 from Qana and the Tab1D_Qact(ib)
        val_mini  = huge(ONE)
        DO iq=1,Tab1D_Qact(ib)%nb_var_vec
          val = abs(ana_psi%Qana(ib)-Tab1D_Qact(ib)%d0(iq))
          IF (val < val_mini) THEN
            val_mini = val
            nDval0(ib) = iq
          END IF
        END DO

        DO jb=1,psi%BasisnD%nb_basis
          nqj = get_nq_FROM_basis(psi%BasisnD%tab_Pbasis(jb)%Pbasis)
          CALL alloc_dnMat(Tab2D_psi2(jb,ib),nb_var_Matl=nqj,nb_var_Matc=nqi)
          CALL alloc_dnMat(Tab2D_Rpsi(jb,ib),nb_var_Matl=nqj,nb_var_Matc=nqi)
          CALL alloc_dnMat(Tab2D_Cpsi(jb,ib),nb_var_Matl=nqj,nb_var_Matc=nqi)
        END DO

      END DO
      !write(out_unitp,*) 'nDval0,Qana',nDval0,ana_psi%Qana

      i_bie = 1

      IF (allocated(psi%CvecG)) THEN

        DO i_qa=1,psi%nb_qa
          i_qaie = i_qa + (i_bie-1) * psi%nb_qa
          val_psi2 = abs(psi%CvecG(i_qaie))**2
          val_Rpsi = Real(psi%CvecG(i_qaie),kind=Rkind)
          val_Cpsi = aimag(psi%CvecG(i_qaie))

          CALL calc_nDindex(psi%BasisnD%nDindG,i_qa,nDval)

          DO ib=1,psi%BasisnD%nb_basis
            nDvalib(:)   = nDval(:)
            nDvalib(ib)  = 0

            nDval0ib(:)  = nDval0(:)
            nDval0ib(ib) = 0

            IF (compare_tab(nDval0ib,nDvalib)) THEN
              Tab1D_psi2(ib)%d0(nDval(ib)) = val_psi2
              Tab1D_Rpsi(ib)%d0(nDval(ib)) = val_Rpsi
              Tab1D_Cpsi(ib)%d0(nDval(ib)) = val_Cpsi
            END IF

            DO jb=ib+1,psi%BasisnD%nb_basis

              nDvalib(jb)  = 0
              nDval0ib(jb) = 0

              IF (compare_tab(nDval0ib,nDvalib)) THEN
                Tab2D_psi2(ib,jb)%d0(nDval(ib),nDval(jb)) = val_psi2
                Tab2D_Rpsi(ib,jb)%d0(nDval(ib),nDval(jb)) = val_Rpsi
                Tab2D_Cpsi(ib,jb)%d0(nDval(ib),nDval(jb)) = val_Cpsi
              END IF

            END DO

          END DO

        END DO
      ELSE IF (allocated(psi%RvecG)) THEN

        DO i_qa=1,psi%nb_qa
          i_qaie = i_qa + (i_bie-1) * psi%nb_qa
          val_psi2 = psi%RvecG(i_qaie)**2
          val_Rpsi = psi%RvecG(i_qaie)
          val_Cpsi = ZERO

          CALL calc_nDindex(psi%BasisnD%nDindG,i_qa,nDval)

          DO ib=1,psi%BasisnD%nb_basis
            nDvalib(:)   = nDval(:)
            nDvalib(ib)  = 0

            nDval0ib(:)  = nDval0(:)
            nDval0ib(ib) = 0

            IF (compare_tab(nDval0ib,nDvalib)) THEN
              Tab1D_psi2(ib)%d0(nDval(ib)) = val_psi2
              Tab1D_Rpsi(ib)%d0(nDval(ib)) = val_Rpsi
              Tab1D_Cpsi(ib)%d0(nDval(ib)) = val_Cpsi
            END IF

            DO jb=ib+1,psi%BasisnD%nb_basis

              nDvalib(jb)  = 0
              nDval0ib(jb) = 0

              IF (compare_tab(nDval0ib,nDvalib)) THEN
                Tab2D_psi2(ib,jb)%d0(nDval(ib),nDval(jb)) = val_psi2
                Tab2D_Rpsi(ib,jb)%d0(nDval(ib),nDval(jb)) = val_Rpsi
                Tab2D_Cpsi(ib,jb)%d0(nDval(ib),nDval(jb)) = val_Cpsi
              END IF

            END DO
          END DO


        END DO

      ELSE
        write(out_unitp,*) 'WARNING in ',name_sub
        write(out_unitp,*) ' Impossible to write CvecG or RvecG'
        RETURN
      END IF


      IF (ana_psi%psi1D_Q0) THEN

        DO ib=1,psi%BasisnD%nb_basis

          state_name = make_FileName('psi1D_')
          !state_name = 'psi1D_'
          IF (ana_psi%adia) state_name = 'psiAdia1D_'
          file_psi%name = state_name // int_TO_char(ana_psi%num_psi) // '-' // int_TO_char(ib)

          IF (ana_psi%propa .AND. ana_psi%T > ZERO) THEN
            CALL file_open(file_psi,nio,append=.TRUE.)
            DO iq=1,Tab1D_Qact(ib)%nb_var_vec
              write(nio,*) ana_psi%T,iq,Tab1D_Qact(ib)%d0(iq),Tab1D_Rpsi(ib)%d0(iq),  &
                             Tab1D_Cpsi(ib)%d0(iq),Tab1D_psi2(ib)%d0(iq)
            END DO
            write(nio,*)
            close(nio)

          ELSE
            CALL file_open(file_psi,nio)
            DO iq=1,Tab1D_Qact(ib)%nb_var_vec
              write(nio,*) iq,Tab1D_Qact(ib)%d0(iq),Tab1D_Rpsi(ib)%d0(iq),  &
                             Tab1D_Cpsi(ib)%d0(iq),Tab1D_psi2(ib)%d0(iq)
            END DO
            close(nio)
          END IF


        END DO
      END IF

      IF (ana_psi%psi2D_Q0) THEN

        DO ib=1,psi%BasisnD%nb_basis
        DO jb=ib+1,psi%BasisnD%nb_basis
          state_name = 'psi2D_'
          IF (ana_psi%adia) state_name = 'psiAdia2D_'
          file_psi%name = state_name // int_TO_char(ana_psi%num_psi) //     &
                  '-' // int_TO_char(ib)  // '-' // int_TO_char(jb)

          IF (ana_psi%propa) THEN
            CALL file_open(file_psi,nio,append=.TRUE.)
            DO iq=1,Tab1D_Qact(ib)%nb_var_vec
            DO jq=1,Tab1D_Qact(jb)%nb_var_vec

              write(nio,*) ana_psi%T,iq,jq,Tab1D_Qact(ib)%d0(iq),Tab1D_Qact(jb)%d0(jq),&
                 Tab2D_Rpsi(ib,jb)%d0(iq,jq),Tab2D_Cpsi(ib,jb)%d0(iq,jq),  &
                                             Tab2D_psi2(ib,jb)%d0(iq,jq)
            END DO
            write(nio,*)
            END DO
            write(nio,*)
            close(nio)

          ELSE
            CALL file_open(file_psi,nio)
            DO iq=1,Tab1D_Qact(ib)%nb_var_vec
            DO jq=1,Tab1D_Qact(jb)%nb_var_vec

              write(nio,*) iq,jq,Tab1D_Qact(ib)%d0(iq),Tab1D_Qact(jb)%d0(jq),&
              Tab2D_Rpsi(ib,jb)%d0(iq,jq),Tab2D_Cpsi(ib,jb)%d0(iq,jq),  &
                                             Tab2D_psi2(ib,jb)%d0(iq,jq)
            END DO
            write(nio,*)
            END DO
            close(nio)
          END IF

        END DO
        END DO
      END IF


      DO ib=1,psi%BasisnD%nb_basis
        CALL dealloc_dnVec(Tab1D_Qact(ib))
        CALL dealloc_dnVec(Tab1D_psi2(ib))
        CALL dealloc_dnVec(Tab1D_Rpsi(ib))
        CALL dealloc_dnVec(Tab1D_Cpsi(ib))
        DO jb=1,psi%BasisnD%nb_basis
          CALL dealloc_dnMat(Tab2D_psi2(jb,ib))
          CALL dealloc_dnMat(Tab2D_Rpsi(jb,ib))
          CALL dealloc_dnMat(Tab2D_Cpsi(jb,ib))
        END DO
      END DO

      IF (allocated(state_name)) deallocate(state_name)

!-----------------------------------------------------------
       IF (debug) THEN
         write(out_unitp,*) 'END ',name_sub
       END IF
!-----------------------------------------------------------


      END SUBROUTINE write1D2D_psi
      SUBROUTINE Rho1D_Rho2D_psi(psi,ana_psi)
      USE mod_system
      USE mod_psi_set_alloc
      USE mod_psi_B_TO_G
      IMPLICIT NONE
!----- variables for the WP ----------------------------------------
      TYPE (param_psi),     intent(inout) :: psi
      TYPE (param_ana_psi), intent(inout) :: ana_psi


!------ working variables ---------------------------------
      TYPE (param_file)              :: file_Rho
      integer                        :: i_basis_act1,j_basis_act1,nioRho
      real (kind=Rkind), allocatable :: rho2D(:,:,:,:)
      real (kind=Rkind), allocatable :: rho1D(:,:,:)


      integer               :: i_qa,i_qaie
      integer               :: i_be,i_bi,i_ba
      integer               :: i_baie,f_baie
      real (kind=Rkind)     :: WrhonD,Weight
      complex (kind=Rkind)  :: temp
      real (kind=Rkind)     :: Rtemp,Qix

      integer :: iq_act1,jq_act1,i,j,iq,ix,ix_TO_iQdyn
      integer :: nDval(psi%BasisnD%nDindG%ndim)
      character (len=:), allocatable  :: state_name

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub='Rho1D_Rho2D_psi'
      logical,parameter :: debug = .FALSE.
!     logical,parameter :: debug = .TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'psi'
        CALL ecri_psi(psi=psi)
      END IF
!-----------------------------------------------------------
      IF (ana_psi%ana .AND. (ana_psi%Rho1D .OR. ana_psi%Rho2D)) THEN
        IF (.NOT. ana_psi%GridDone) CALL sub_PsiBasisRep_TO_GridRep(psi)

        IF (ana_psi%Rho1D) THEN
          !- loop on coordinates ----------------------------------
          DO i_basis_act1=1,psi%BasisnD%nb_basis

            state_name = make_FileName('Rho1D_')
            !state_name = 'Rho1D_'
            IF (ana_psi%adia) state_name = 'RhoAdia1D_'
            file_Rho%name = state_name // int_TO_char(ana_psi%num_psi) // &
                                    '-' // int_TO_char(i_basis_act1)

            IF (ana_psi%propa .AND. ana_psi%T > ZERO) THEN
              CALL file_open(file_Rho,nioRho,append=.TRUE.)
            ELSE
              CALL file_open(file_Rho,nioRho)
            END IF

            CALL alloc_NParray(rho1D,                                   &
                 (/psi%BasisnD%nDindG%nDsize(i_basis_act1),psi%nb_bi,psi%nb_be/), &
                              'rho1D',name_sub)
            rho1D(:,:,:) = ZERO


            DO i_qa=1,psi%nb_qa

              CALL calc_nDindex(psi%BasisnD%nDindG,i_qa,nDval)

              !- calculation of WrhonD ------------------------------
              WrhonD   = ONE
              DO i=1,psi%BasisnD%nb_basis
                iq  = nDval(i)

                IF (allocated(ana_psi%Weight_Rho) .AND.            &
                              allocated(ana_psi%Qana_weight) ) THEN

                  DO ix=1,psi%BasisnD%tab_Pbasis(i)%Pbasis%ndim
                    ix_TO_iQdyn = psi%BasisnD%tab_Pbasis(i)%Pbasis%iQdyn(ix)
                    IF (ana_psi%Weight_Rho(ix_TO_iQdyn) == 1) THEN
                      Qix = psi%BasisnD%tab_Pbasis(i)%Pbasis%x(ix,iq)
                      IF (Qix > ana_psi%Qana_weight(ix_TO_iQdyn)) THEN
                        WrhonD   = ZERO
                      END IF
                    ELSE IF (ana_psi%Weight_Rho(ix_TO_iQdyn) == -1) THEN
                      Qix = psi%BasisnD%tab_Pbasis(i)%Pbasis%x(ix,iq)
                      IF (Qix < ana_psi%Qana_weight(ix_TO_iQdyn)) THEN
                        WrhonD   = ZERO
                      END IF
                    END IF
                  END DO

                END IF

                IF (WrhonD == ZERO) CYCLE

                IF (i == i_basis_act1) THEN
                  IF (ana_psi%Rho_type == 1) THEN
                    WrhonD = WrhonD * Rec_WrhonD(psi%BasisnD%tab_Pbasis(i)%Pbasis,iq)
                  ELSE IF (ana_psi%Rho_type == 2) THEN
                    WrhonD = WrhonD * Rec_rhonD(psi%BasisnD%tab_Pbasis(i)%Pbasis,iq)
                  END IF
                ELSE
                  WrhonD = WrhonD * Rec_WrhonD(psi%BasisnD%tab_Pbasis(i)%Pbasis,iq)
                END IF
              END DO

              DO i_be=1,psi%nb_be
              DO i_bi=1,psi%nb_bi
                i_qaie=i_qa + ( (i_bi-1)+(i_be-1)*psi%nb_bi ) * psi%nb_qa

                IF (psi%cplx) THEN
                  temp = conjg(psi%CvecG(i_qaie))*psi%CvecG(i_qaie)
                ELSE
                  temp = cmplx(psi%RvecG(i_qaie)*psi%RvecG(i_qaie),ZERO,kind=Rkind)
                END IF

                iq_act1 = nDval(i_basis_act1)
                rho1D(iq_act1,i_bi,i_be) = rho1D(iq_act1,i_bi,i_be) + WrhonD * real(temp,kind=Rkind)
              END DO
              END DO
            END DO

            write(out_unitp,*) 'rho1D of ',ana_psi%num_psi,i_basis_act1
            IF (ana_psi%propa) THEN
              DO i=1,psi%BasisnD%nDindG%nDsize(i_basis_act1)
                write(nioRho,*) ana_psi%T,ana_psi%num_psi,i,                &
                  psi%BasisnD%tab_Pbasis(i_basis_act1)%Pbasis%x(:,i),rho1D(i,:,:)
              END DO
              write(nioRho,*)
            ELSE
              DO i=1,psi%BasisnD%nDindG%nDsize(i_basis_act1)
                write(nioRho,*) ana_psi%num_psi,i,                          &
                  psi%BasisnD%tab_Pbasis(i_basis_act1)%Pbasis%x(:,i),rho1D(i,:,:)
              END DO
            END IF



            CALL dealloc_NParray(rho1D,'rho1D',name_sub)
            close(nioRho)
          END DO
        END IF

        IF (ana_psi%Rho2D) THEN

          !- loop on coordinates ----------------------------------
          DO i_basis_act1=1,psi%BasisnD%nb_basis
          DO j_basis_act1=i_basis_act1+1,psi%BasisnD%nb_basis

            state_name = 'Rho2D_'
            IF (ana_psi%adia) state_name = 'RhoAdia2D_'
            file_Rho%name = state_name // int_TO_char(ana_psi%num_psi) // &
               '-' // int_TO_char(i_basis_act1) // '-' // int_TO_char(j_basis_act1)

            IF (ana_psi%propa) THEN
              CALL file_open(file_Rho,nioRho,append=.TRUE.)
            ELSE
              CALL file_open(file_Rho,nioRho)
            END IF

            CALL alloc_NParray(rho2D,                                   &
                            (/psi%BasisnD%nDindG%nDsize(i_basis_act1),  &
                              psi%BasisnD%nDindG%nDsize(j_basis_act1),  &
                              psi%nb_bi,psi%nb_be/),'rho2D',name_sub)
            rho2D(:,:,:,:) = ZERO

            DO i_qa=1,psi%nb_qa

              CALL calc_nDindex(psi%BasisnD%nDindG,i_qa,nDval)

              !- calculation of WrhonD ------------------------------
              WrhonD   = ONE
              DO i=1,psi%BasisnD%nb_basis
                iq  = nDval(i)

                IF (allocated(ana_psi%Weight_Rho) .AND.            &
                              allocated(ana_psi%Qana_weight) ) THEN
                  DO ix=1,psi%BasisnD%tab_Pbasis(i)%Pbasis%ndim
                    ix_TO_iQdyn = psi%BasisnD%tab_Pbasis(i)%Pbasis%iQdyn(ix)

                    IF (ana_psi%Weight_Rho(ix_TO_iQdyn) == 1) THEN
                      Qix = psi%BasisnD%tab_Pbasis(i)%Pbasis%x(ix,iq)
                      IF (Qix > ana_psi%Qana_weight(ix_TO_iQdyn)) THEN
                        WrhonD   = ZERO
                      END IF
                    ELSE IF (ana_psi%Weight_Rho(ix_TO_iQdyn) == -1) THEN
                      Qix = psi%BasisnD%tab_Pbasis(i)%Pbasis%x(ix,iq)
                      IF (Qix < ana_psi%Qana_weight(ix_TO_iQdyn)) THEN
                        WrhonD   = ZERO
                      END IF
                    END IF
                  END DO

                  IF (WrhonD == ZERO) CYCLE
                END IF


                IF (i == i_basis_act1 .OR. i == j_basis_act1) THEN
                  IF (ana_psi%Rho_type == 1) THEN
                    WrhonD = WrhonD * Rec_WrhonD(psi%BasisnD%tab_Pbasis(i)%Pbasis,iq)
                  ELSE IF (ana_psi%Rho_type == 2) THEN
                    WrhonD = WrhonD * Rec_rhonD(psi%BasisnD%tab_Pbasis(i)%Pbasis,iq)
                  END IF
                ELSE
                  WrhonD = WrhonD * Rec_WrhonD(psi%BasisnD%tab_Pbasis(i)%Pbasis,iq)
                END IF
              END DO

              DO i_be=1,psi%nb_be
              DO i_bi=1,psi%nb_bi
                i_qaie=i_qa + ( (i_bi-1)+(i_be-1)*psi%nb_bi ) * psi%nb_qa

                IF (psi%cplx) THEN
                  temp = conjg(psi%CvecG(i_qaie))*psi%CvecG(i_qaie)
                ELSE
                  temp = cmplx(psi%RvecG(i_qaie)*psi%RvecG(i_qaie),ZERO,kind=Rkind)
                END IF

                iq_act1 = nDval(i_basis_act1)
                jq_act1 = nDval(j_basis_act1)
                rho2D(iq_act1,jq_act1,i_bi,i_be) = rho2D(iq_act1,jq_act1,i_bi,i_be) +       &
                                       WrhonD * real(temp,kind=Rkind)
              END DO
              END DO
            END DO

            write(out_unitp,*) 'rho2D of ',ana_psi%num_psi,i_basis_act1,j_basis_act1
            IF (ana_psi%propa) THEN
              DO i=1,psi%BasisnD%nDindG%nDsize(i_basis_act1)
              DO j=1,psi%BasisnD%nDindG%nDsize(j_basis_act1)
                write(nioRho,*) ana_psi%T,ana_psi%num_psi,i,j,              &
                 psi%BasisnD%tab_Pbasis(i_basis_act1)%Pbasis%x(:,i),    &
                 psi%BasisnD%tab_Pbasis(j_basis_act1)%Pbasis%x(:,j),    &
                 rho2D(i,j,:,:)
              END DO
              write(nioRho,*)
              END DO
              write(nioRho,*)
            ELSE
              DO i=1,psi%BasisnD%nDindG%nDsize(i_basis_act1)
              DO j=1,psi%BasisnD%nDindG%nDsize(j_basis_act1)
                write(nioRho,*) ana_psi%num_psi,i,j,                        &
                 psi%BasisnD%tab_Pbasis(i_basis_act1)%Pbasis%x(:,i),    &
                 psi%BasisnD%tab_Pbasis(j_basis_act1)%Pbasis%x(:,j),    &
                 rho2D(i,j,:,:)
              END DO
              write(nioRho,*)
              END DO
            END IF

            CALL dealloc_NParray(rho2D,'rho2D',name_sub)
            close(nioRho)
          END DO
          END DO
        END IF

      END IF

      IF (allocated(state_name)) deallocate(state_name)

!----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!----------------------------------------------------------


      END SUBROUTINE Rho1D_Rho2D_psi

!==============================================================
!
!      calc_1Dweight(psi)
!
!==============================================================
      SUBROUTINE calc_1Dweight(psi,ana_psi,tab_WeightChannels,max_1D,T,info,print_w)
      USE mod_system
      USE mod_dnSVM
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP propagation ----------------------------
      TYPE (param_psi)     :: psi
      TYPE (param_ana_psi) :: ana_psi
      real (kind=Rkind), allocatable :: tab_WeightChannels(:,:)

      integer              :: max_1D
      real (kind=Rkind)    :: T ! time
      character (len=*)    :: info
      logical              :: print_w


!----- for debuging --------------------------------------------------
      integer :: err_mem
      character (len=*), parameter :: name_sub='calc_1Dweight'
      logical, parameter :: debug =.FALSE.
!      logical, parameter :: debug =.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        CALL RecWrite_basis(psi%BasisnD,write_all=.TRUE.)
        CALL flush_perso(out_unitp)
      END IF
!-----------------------------------------------------------

      !CALL Set_symab_OF_psiBasisRep(psi)

      IF (psi%nb_baie*psi%nb_bRot == psi%nb_tot) THEN
        CALL calc_1Dweight_act1(psi,ana_psi,max_1D,T,info,print_w)
      END IF

      CALL calc_1Dweight_inact2n_elec(psi,ana_psi,tab_WeightChannels,max_1D,T,info,print_w)

!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!-----------------------------------------------------------


      END SUBROUTINE calc_1Dweight

      SUBROUTINE calc_1Dweight_inact2n_elec(psi,ana_psi,tab_WeightChannels,&
                                            max_1D,T,info,print_w)
      USE mod_system
      USE mod_nDindex
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP propagation ----------------------------
      TYPE (param_psi)     :: psi
      TYPE (param_ana_psi) :: ana_psi

      integer          :: max_herm
      real (kind=Rkind),allocatable :: weight1D(:,:)
      integer          :: tab(psi%Basis2n%nb_basis+1)

     real (kind=Rkind), allocatable :: tab_WeightChannels(:,:)
      real (kind=Rkind),allocatable :: weight1Dact(:,:)
      real (kind=Rkind)    :: a

      real (kind=Rkind)    :: T ! time
      character (len=*)    :: info
      logical          :: print_w

      integer              :: i,j,j_herm,beg_e
      integer              :: ie,ii,ib,ibie,iq,ibiq
      integer              :: max_dim,max_1D
      integer, allocatable :: nDval(:)

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub='calc_1Dweight_inact2n_elec'
      integer :: err_mem,memory
      logical, parameter :: debug =.FALSE.
!      logical, parameter :: debug =.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'nb_inact2n',psi%Basis2n%nb_basis
        write(out_unitp,*) 'nb_bi,nb_be',psi%nb_bi,psi%nb_be
        write(out_unitp,*) 'nb_bie',psi%nb_bi*psi%nb_be
        !write(out_unitp,*) 'tab_WeightChannels',tab_WeightChannels
        CALL flush_perso(out_unitp)
      END IF
!-----------------------------------------------------------
      IF (ana_psi%adia) RETURN

      IF (.NOT. allocated(tab_WeightChannels)) THEN
        write(out_unitp,*) 'ERROR in ',name_sub
        write(out_unitp,*) 'tab_WeightChannels is not allocated!!'
        write(out_unitp,*) ' It should be done in sub_analyze or sub_analyze_WP_forPropa'
        STOP
      END IF

      IF (psi%Basis2n%nb_basis == 0) THEN
        max_herm = psi%nb_be-1
      ELSE
        CALL alloc_NParray(nDval,(/psi%Basis2n%nb_basis/),'nDval',name_sub)
        max_herm = 0
        DO i=1,psi%Basis2n%nb_basis
          IF (psi%Basis2n%tab_Pbasis(i)%Pbasis%nb > max_herm)           &
                      max_herm = psi%Basis2n%tab_Pbasis(i)%Pbasis%nb
        END DO
        max_herm = max_herm - 1
      END IF

      CALL alloc_NParray(weight1D,(/psi%Basis2n%nb_basis+1,max_herm/),    &
                        "weight1D",name_sub,(/1,0/))

      IF (psi%nb_bi > 1 .OR. psi%nb_be > 1) THEN
        weight1D(:,:) = ZERO
        i = 0
        DO ie=1,psi%nb_be
        DO ii=1,psi%nb_bi
          i = i + 1
          IF (psi%Basis2n%nb_basis > 0) THEN
            CALL calc_nDindex(psi%Basis2n%nDindB,i,nDval)
            tab(1:psi%Basis2n%nb_basis) = nDval(:)-1
            tab(psi%Basis2n%nb_basis+1) = ie
          ELSE
            tab(psi%Basis2n%nb_basis+1) = ie-1
          END IF


          DO j=1,psi%Basis2n%nb_basis+1
            j_herm = tab(j)
            weight1D(j,j_herm) = weight1D(j,j_herm) + tab_WeightChannels(ii,ie)
          END DO
        END DO
        END DO

        IF (print_w .OR. debug) THEN
          DO i=1,psi%Basis2n%nb_basis
            write(out_unitp,11) 'harm T W ',trim(info),i,T,             &
                    weight1D(i,0:psi%Basis2n%tab_Pbasis(i)%Pbasis%nb-1)
          END DO
          beg_e = 1
          IF (psi%Basis2n%nb_basis == 0) beg_e = 0
          i = psi%Basis2n%nb_basis+1
          write(out_unitp,11) 'elec T W ',trim(info),i,T,               &
                weight1D(i,beg_e:beg_e+psi%nb_be-1)

 11       format(a,a,1x,i3,1x,f15.2,20(1x,f6.3))
        END IF
      END IF

      CALL dealloc_NParray(weight1D,"weight1D",name_sub)
      IF (allocated(nDval)) CALL dealloc_NParray(nDval,'nDval',name_sub)

!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!-----------------------------------------------------------



      END SUBROUTINE calc_1Dweight_inact2n_elec

      SUBROUTINE calc_MaxCoef_psi(psi,T,info)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP propagation ----------------------------
      TYPE (param_psi)     :: psi

      real (kind=Rkind)    :: T ! time
      character (len=*)    :: info

      real (kind=Rkind)  :: C,maxC1,maxC2
      integer            :: i_bhe,i_b,i_e,i_h,i_R
      integer            :: i_bhe1,i_bhe2,i_b_maxC1,i_b_maxC2
      integer            :: i_R_maxC1,i_R_maxC2
      integer            :: i_e_maxC1,i_e_maxC2
      integer            :: i_h_maxC1,i_h_maxC2
      integer            :: ndim_index(psi%BasisnD%ndim)


!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub='calc_MaxCoef_psi'
      logical, parameter :: debug =.FALSE.
      !logical, parameter :: debug =.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'asso psi%BasisnD',associated(psi%BasisnD)
        CALL flush_perso(out_unitp)
      END IF
!-----------------------------------------------------------
      IF (psi%nb_baie*psi%nb_bRot /= psi%nb_tot .AND.                   &
          .NOT. psi%ComOp%contrac_ba_ON_HAC) RETURN   ! should be spectral WP

      maxC1 = ZERO
      maxC2 = ZERO
      i_b_maxC1 = 0
      i_b_maxC2 = 0
      i_h_maxC1 = 0
      i_h_maxC2 = 0
      i_e_maxC1 = 0
      i_e_maxC2 = 0
      i_R_maxC1 = 0
      i_R_maxC2 = 0
      i_bhe1    = 0
      i_bhe2    = 0

      i_bhe = 0
      DO i_R=1,psi%nb_bRot
      DO i_e=1,psi%nb_be
      DO i_h=1,psi%nb_bi
      DO i_b=1,psi%ComOp%nb_ba_ON_HAC(i_h)
      !DO i_b=1,psi%nb_ba

        i_bhe = i_bhe + 1

        IF (psi%cplx) THEN
          C = abs(psi%CvecB(i_bhe))
        ELSE
          C = abs(psi%RvecB(i_bhe))
        END IF

        IF ( C > maxC1) THEN
          ! test if maxC1 > maxC2 (the old maxC1)
          IF ( maxC1 > maxC2) THEN
            maxC2     = maxC1
            i_bhe2    = i_bhe1
            i_b_maxC2 = i_b_maxC1
            i_h_maxC2 = i_h_maxC1
            i_e_maxC2 = i_e_maxC1
            i_R_maxC2 = i_R_maxC1
          END IF
          maxC1     = C
          i_bhe1    = i_bhe
          i_b_maxC1 = i_b
          i_h_maxC1 = i_h
          i_e_maxC1 = i_e
          i_R_maxC1 = i_R
        ELSE IF ( C > maxC2) THEN
          maxC2     = C
          i_bhe2    = i_bhe
          i_b_maxC2 = i_b
          i_h_maxC2 = i_h
          i_e_maxC2 = i_e
          i_R_maxC2 = i_R
        END IF
        !write(out_unitp,*) i_bhe,C,'i_b_maxC1,i_b_maxC2',i_b_maxC1,i_b_maxC2
      END DO
      END DO
      END DO
      END DO

      IF (psi%ComOp%contrac_ba_ON_HAC) THEN

        IF (psi%cplx) THEN
          write(out_unitp,*) 'max1 psi%vecBasisRep ',T,trim(info),      &
                         i_b_maxC1,i_h_maxC1,i_e_maxC1,psi%CvecB(i_bhe1)
          IF (i_b_maxC2 > 0)                                            &
               write(out_unitp,*) 'max2 psi%vecBasisRep ',T,trim(info), &
                          i_b_maxC2,i_h_maxC2,i_e_maxC2,psi%CvecB(i_bhe2)
        ELSE
          write(out_unitp,*) 'max1 psi%vecBasisRep ',T,trim(info),      &
                         i_b_maxC1,i_h_maxC1,i_e_maxC1,psi%RvecB(i_bhe1)
          IF (i_b_maxC2 > 0)                                            &
               write(out_unitp,*) 'max2 psi%vecBasisRep ',T,trim(info), &
                          i_b_maxC2,i_h_maxC2,i_e_maxC2,psi%RvecB(i_bhe2)
        END IF
      ELSE
        IF (i_b_maxC1 < 1 .OR. i_b_maxC1 > psi%nb_ba) THEN
          write(out_unitp,*) '   WARNING, i_b_maxC1 is out-of-range !! ',i_b_maxC1
          write(out_unitp,*) '    it should > 0 and <= nb_ba'
        ELSE
          CALL Rec_ndim_index(psi%BasisnD,ndim_index,i_b_maxC1)
          IF (psi%cplx) THEN
            write(out_unitp,*) 'max1 psi%vecBasisRep ',T,trim(info),      &
                        ndim_index(:),i_h_maxC1,i_e_maxC1,psi%CvecB(i_bhe1)

            IF (i_b_maxC2 > 0) THEN
              CALL Rec_ndim_index(psi%BasisnD,ndim_index,i_b_maxC2)
              write(out_unitp,*) 'max2 psi%vecBasisRep ',T,trim(info),    &
                        ndim_index(:),i_h_maxC2,i_e_maxC2,psi%CvecB(i_bhe2)
            END IF
          ELSE
            write(out_unitp,*) 'max1 psi%vecBasisRep ',T,trim(info),      &
                        ndim_index(:),i_h_maxC1,i_e_maxC1,psi%RvecB(i_bhe1)

            IF (i_b_maxC2 > 0) THEN
              CALL Rec_ndim_index(psi%BasisnD,ndim_index,i_b_maxC2)
              write(out_unitp,*) 'max2 psi%vecBasisRep ',T,trim(info),    &
                        ndim_index(:),i_h_maxC2,i_e_maxC2,psi%RvecB(i_bhe2)
            END IF

          END IF
        END IF


      END IF
      write(out_unitp,*) 'Abelian symmetry (symab):',psi%symab
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!-----------------------------------------------------------

      end subroutine calc_MaxCoef_psi

      SUBROUTINE calc_1Dweight_act1(psi,ana_psi,max_1D,T,info,print_w)
      USE mod_system
      USE mod_nDindex
      USE mod_psi_set_alloc
      USE mod_type_ana_psi
      USE mod_param_RD
      USE mod_MPI
      IMPLICIT NONE

!----- variables for the WP propagation ----------------------------
      TYPE (param_psi)     :: psi
      TYPE (param_ana_psi) :: ana_psi

      real (kind=Rkind), allocatable :: weight1Dact(:,:)
      real (kind=Rkind)    :: a

      real (kind=Rkind)    :: T ! time
      character (len=*)    :: info
      logical          :: print_w

      integer          :: i,ie,ii,ib,ibie,iq,ibiq,n
      integer          :: max_dim,max_1D
      integer          :: max_indGr(psi%BasisnD%nDindB%ndim)
      integer          :: ndim_AT_ib(psi%BasisnD%nDindB%ndim)
      integer          :: nDval(psi%BasisnD%nDindB%ndim)

      character (len=:), allocatable :: state_name

      real (kind=Rkind)              :: r2
      real (kind=Rkind), allocatable :: DiagRDcontrac(:) ! diagonal reduced density matrix with the contracted basis set (nbc,nbc)

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub='calc_1Dweight_act1'
      logical, parameter :: debug =.FALSE.
!     logical, parameter :: debug =.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'nb_inact2n',psi%Basis2n%nb_basis
        write(out_unitp,*) 'nb_bi,nb_be',psi%nb_bi,psi%nb_be
      END IF
!-----------------------------------------------------------
      CALL flush_perso(out_unitp)
      IF (psi%nb_baie /= psi%nb_tot) RETURN
      IF (ana_psi%adia) RETURN

      IF (allocated(Psi%BasisnD%nDindB%Tab_nDval)) THEN
        max_dim = maxval(Psi%BasisnD%nDindB%Tab_nDval)
      ELSE
        max_dim = maxval(psi%BasisnD%nDindB%nDsize(1:psi%BasisnD%nDindB%ndim))
      END IF
      CALL alloc_NParray(weight1Dact,(/psi%BasisnD%nDindB%ndim,max_dim/), &
                        "weight1Dact",name_sub)

    ibie = 0
    DO ie=1,psi%nb_be
    DO ii=1,psi%nb_bi
      weight1Dact(:,:) = ZERO
      ndim_AT_ib(:)    = 0
      IF (ie == 1 .AND. ii == 1) THEN
        state_name = 'Grd Channel'
      ELSE
        state_name = 'State_Se' // int_TO_char(ie) // '_Cha' // int_TO_char(ii)
      END IF

      IF (psi%cplx) THEN

        DO ib=1,psi%nb_ba
          ibie = ibie + 1
          a = abs(psi%CvecB(ibie))**2

          CALL calc_nDindex(psi%BasisnD%nDindB,ib,nDval)

          DO iq=1,psi%BasisnD%nDindB%ndim
            ibiq = nDval(iq)
            ndim_AT_ib(iq) = max(ibiq,ndim_AT_ib(iq))
            !write(out_unitp,*) 'calc_1Dweight',iq,ibiq,ib
            weight1Dact(iq,ibiq) = weight1Dact(iq,ibiq) + a
          END DO
        END DO
      ELSE

        DO ib=1,psi%nb_ba
          ibie = ibie + 1
          a = psi%RvecB(ibie)**2

          CALL calc_nDindex(psi%BasisnD%nDindB,ib,nDval)

          DO iq=1,psi%BasisnD%nDindB%ndim
            ibiq = nDval(iq)
            ndim_AT_ib(iq) = max(ibiq,ndim_AT_ib(iq))
            !write(out_unitp,*) 'calc_1Dweight',iq,ibiq,ib
            weight1Dact(iq,ibiq) = weight1Dact(iq,ibiq) + a
          END DO
        END DO
      END IF

      !write(out_unitp,*) 'ndim_AT_ib',ndim_AT_ib(:)
      IF (print_w .OR. debug) THEN
        DO iq=1,psi%BasisnD%nDindB%ndim
          IF (sum(weight1Dact(iq,1:ndim_AT_ib(iq)))-ONE > ONETENTH**7)  &
                write(out_unitp,21) state_name // ' Sum(RD)/=1',trim(info),&
                             iq,T,sum(weight1Dact(iq,1:ndim_AT_ib(iq)))
          IF(MPI_id==0) write(out_unitp,21) state_name // ' ',trim(info),iq,T,           &
                           weight1Dact(iq,1:min(max_1D,ndim_AT_ib(iq)))
 21       format(a,a,i3,1x,f17.4,300(1x,e10.3))
          CALL flush_perso(out_unitp)

          IF (allocated(psi%BasisnD%para_RD)) THEN
          IF (psi%BasisnD%para_RD(iq)%RD_analysis) THEN

            CALL calc_RD(psi%BasisnD%para_RD(iq),psi%RvecB,DiagRDcontrac=DiagRDcontrac)
            n = min(ndim_AT_ib(iq),size(DiagRDcontrac))
            weight1Dact(iq,1:n) = DiagRDcontrac(1:n)
            write(out_unitp,21) state_name // 'c',trim(info),iq,T,           &
                           weight1Dact(iq,1:min(max_1D,n))
            CALL flush_perso(out_unitp)

            !write(out_unitp,*) 'Diag RD contracted',iq,DiagRDcontrac
            IF (allocated(DiagRDcontrac)) CALL dealloc_NParray(DiagRDcontrac,'DiagRDcontrac',name_sub)
          END IF
          END IF


          max_indGr(iq) = sum(maxloc(weight1Dact(iq,1:ndim_AT_ib(iq))))
        END DO

        !write(out_unitp,'(a,a,20i4)') 'max_indGr at ',trim(info),max_indGr(:)
        write(out_unitp,'(a,a)',advance='no') 'max_ind ' // state_name // ' at ',trim(info)
        DO i=1,size(max_indGr)-1
          write(out_unitp,'(1X,i0)',advance='no') max_indGr(i)
        END DO
        write(out_unitp,'(1X,i0)') max_indGr(size(max_indGr))

        CALL flush_perso(out_unitp)
      END IF

      !write(out_unitp,*) 'max_RedDensity
      IF (.NOT. allocated(ana_psi%max_RedDensity)) THEN
        CALL alloc_NParray(ana_psi%max_RedDensity,(/psi%BasisnD%nDindB%ndim/), &
                          "ana_psi%max_RedDensity",name_sub)
      END IF
      DO iq=1,psi%BasisnD%nDindB%ndim
        ana_psi%max_RedDensity(iq) = ZERO
        DO ib=1,ndim_AT_ib(iq)
          r2 = real(ndim_AT_ib(iq)-ib,kind=Rkind)**2
          ana_psi%max_RedDensity(iq) = ana_psi%max_RedDensity(iq) + weight1Dact(iq,ib)*exp(-r2)
        END DO
      END DO
      !write(out_unitp,*) 'max_RedDensity ',ana_psi%max_RedDensity(:)
      CALL Write_Vec(ana_psi%max_RedDensity,out_unitp,6,Rformat='e9.2',name_info='max_RedDensity of ' // state_name)
      CALL flush_perso(out_unitp)

    END DO
    END DO
    CALL dealloc_NParray(weight1Dact,"weight1Dact",name_sub)
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!-----------------------------------------------------------

      END SUBROUTINE calc_1Dweight_act1


!=======================================================================================      
!     norm^2 of psi (BasisRep or GridRep)
!=======================================================================================      
      SUBROUTINE norm2_psi(psi,GridRep,BasisRep,ReNorm)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP ----------------------------------------
      TYPE (param_psi), intent(inout) :: psi
      logical, intent(in), optional   :: ReNorm,GridRep,BasisRep

!------ working variables ---------------------------------
      integer       :: i_qa,i_qaie
      integer       :: i_be,i_bi,i_ba,i_baie
      integer       :: ii_baie,if_baie
      real (kind=Rkind) :: WrhonD,temp
      integer       :: i_max_w

      logical       :: psiN,norm2GridRep,norm2BasisRep

      real (kind=Rkind), allocatable :: tab_WeightChannels(:,:)


!----- for debuging --------------------------------------------------
      logical,parameter :: debug = .FALSE.
      !logical,parameter :: debug = .TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING norm2_psi'
        IF (present(ReNorm)) write(out_unitp,*) 'Renormalization of psi',ReNorm
        IF (present(GridRep)) write(out_unitp,*) 'norm2GridRep',GridRep
        IF (present(BasisRep)) write(out_unitp,*) 'norm2BasisRep',BasisRep
        write(out_unitp,*) 'psi'
        CALL ecri_psi(psi=psi)
      END IF
!-----------------------------------------------------------

      IF (present(ReNorm)) THEN
        psiN = ReNorm
      ELSE
        psiN = .FALSE.
      END IF

      IF (present(GridRep)) THEN
        IF (present(BasisRep)) THEN
          norm2GridRep  = GridRep
          norm2BasisRep = BasisRep
        ELSE
          norm2GridRep  = GridRep
          norm2BasisRep = .FALSE.
        END IF
      ELSE
        IF (present(BasisRep)) THEN
          norm2BasisRep = BasisRep
          norm2GridRep  = .FALSE.
        ELSE
          IF (psi%BasisRep .AND. psi%GridRep) THEN
            norm2BasisRep = .TRUE.
            norm2GridRep  = .FALSE.
          ELSE
            norm2BasisRep = psi%BasisRep
            norm2GridRep  = psi%GridRep
          END IF
       END IF
     END IF

      IF (debug) write(out_unitp,*) 'nGridRep,nBasisRep,psiN',norm2GridRep,norm2BasisRep,psiN
      IF (norm2GridRep .AND. norm2BasisRep) THEN
        write(out_unitp,*) ' ERROR in norm2_psi'
        write(out_unitp,*) ' norm2GridRep=t and norm2BasisRep=t !'
        write(out_unitp,*) ' BasisRep,GridRep',psi%BasisRep,psi%GridRep
        STOP
      END IF


      CALL Channel_weight(tab_WeightChannels,psi,norm2GridRep,norm2BasisRep)

      IF (debug)  write(out_unitp,*) 'tab_WeightChannels : ',tab_WeightChannels

      psi%norm2 = sum(tab_WeightChannels)

      IF (debug) THEN
        write(out_unitp,*) 'norm2 : ',psi%norm2,tab_WeightChannels
      END IF



      IF (psiN) THEN

        IF (psi%norm2 .EQ. ZERO ) THEN
          write(out_unitp,*) ' ERROR in norm2_psi'
          write(out_unitp,*) ' the norm2 is zero !',psi%norm2
          STOP
        END IF
        temp = ONE/psi%norm2
        tab_WeightChannels = tab_WeightChannels * temp
        temp = sqrt(temp)

        IF (norm2GridRep) THEN
!         - normalization of psiGridRep -------------------------
          IF (psi%cplx) THEN
            psi%CvecG(:) = psi%CvecG(:) *cmplx(temp,ZERO,kind=Rkind)
          ELSE
            psi%RvecG(:) = psi%RvecG(:) * temp
          END IF
        ELSE
!         - normalization of psiBasisRep -------------------------
          IF (psi%cplx) THEN
            psi%CvecB(:) = psi%CvecB(:) *cmplx(temp,ZERO,kind=Rkind)
          ELSE
            psi%RvecB(:) = psi%RvecB(:) * temp
          END IF
        END IF
        psi%norm2 = ONE
      END IF

      IF (allocated(tab_WeightChannels)) THEN
        CALL dealloc_NParray(tab_WeightChannels,"tab_WeightChannels","norm2_psi (alloc from Channel_weight)")
      END IF

!----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'norm2 : ',psi%norm2,tab_WeightChannels
        write(out_unitp,*) 'END norm2_psi'
      END IF
!----------------------------------------------------------

      END SUBROUTINE norm2_psi
!=======================================================================================

#if(run_MPI)
!=======================================================================================      
!> MPI norm^2 of psi (BasisRep or GridRep)
!> NOTE: ReNorm controls if nromalizing the the vector or
!> just keep the nromalization constrant
!=======================================================================================      
SUBROUTINE norm_psi_MPI(psi,ReNorm,GridRep,BasisRep)
  USE mod_system
  USE mod_psi_set_alloc
  USE mod_MPI
  IMPLICIT NONE

  TYPE(param_psi),intent(inout)           :: psi
  Integer,intent(in)                      :: ReNorm
  Logical,optional,intent(in)             :: GridRep
  Logical,optional,intent(in)             :: BasisRep

  Real(kind=Rkind),allocatable            :: tab_WeightChannels(:,:)
  Real(kind=Rkind)                        :: WrhonD
  Real(kind=Rkind)                        :: temp
  Integer                                 :: i_qa
  Integer                                 :: i_qaie
  Integer                                 :: i_be
  Integer                                 :: i_bi
  Integer                                 :: i_ba
  Integer                                 :: i_baie
  Integer                                 :: ii_baie
  Integer                                 :: if_baie
  Integer                                 :: i_max_w
  Logical                                 :: norm2GridRep
  Logical                                 :: norm2BasisRep

  IF(present(GridRep)) THEN
    IF(present(BasisRep)) THEN
      norm2GridRep =GridRep
      norm2BasisRep=BasisRep
    ELSE
      norm2GridRep =GridRep
      norm2BasisRep=.FALSE.
    ENDIF
  ELSE
    IF(present(BasisRep)) THEN
      norm2BasisRep = BasisRep
      norm2GridRep  = .FALSE.
    ELSE
      IF(psi%BasisRep .AND. psi%GridRep) THEN
        norm2BasisRep = .TRUE.
        norm2GridRep  = .FALSE.
      ELSE
        norm2BasisRep = psi%BasisRep
        norm2GridRep  = psi%GridRep
      ENDIF
    ENDIF
  ENDIF

  IF (norm2GridRep .AND. norm2BasisRep) THEN
    write(out_unitp,*) ' ERROR in norm2_psi'
    write(out_unitp,*) ' norm2GridRep=t and norm2BasisRep=t !'
    write(out_unitp,*) ' BasisRep,GridRep',psi%BasisRep,psi%GridRep
    STOP
  ENDIF
  
  IF(ReNorm==1 .OR. ReNorm==3) THEN
    ! NOTE: tab_WeightChannels obtained correctly only on master
    CALL Channel_weight_MPI(tab_WeightChannels,psi,norm2GridRep,norm2BasisRep)

    IF(MPI_id==0) psi%norm2=sum(tab_WeightChannels)
    CALL MPI_Bcast(psi%norm2,size1_MPI,MPI_Real8,root_MPI,MPI_COMM_WORLD,MPI_err)
    
    IF (allocated(tab_WeightChannels)) THEN
      CALL dealloc_NParray(tab_WeightChannels,"tab_WeightChannels","Channel_weight")
    END IF
  ENDIF
  
  IF(ReNorm==2 .OR. ReNorm==3) THEN
    IF (psi%norm2 .EQ. ZERO ) THEN
      write(out_unitp,*) ' ERROR in norm2_psi'
      write(out_unitp,*) ' the norm2 is zero !',psi%norm2
      STOP
    END IF
    
    temp=sqrt(ONE/psi%norm2)

    !-normalization---------------------------------------------------------------------
    IF(norm2GridRep) THEN
      IF(psi%cplx) THEN
        psi%CvecG=psi%CvecG*cmplx(temp,ZERO,kind=Rkind)
      ELSE
        psi%RvecG=psi%RvecG*temp
      ENDIF
    ELSE
      IF(psi%cplx) THEN
        psi%CvecB=psi%CvecB*cmplx(temp,ZERO,kind=Rkind)
      ELSE
        psi%RvecB=psi%RvecB*temp
      ENDIF
    ENDIF
    psi%norm2=ONE
  ENDIF
    
  IF(.NOT. (ReNorm==1 .OR. ReNorm==2 .OR. ReNorm==3)) THEN
    STOP 'error in norm_psi_MPI, ReNorm not provided '
  ENDIF ! for ReNorm

END SUBROUTINE norm_psi_MPI
!=======================================================================================
#endif

!=======================================================================================
      SUBROUTINE renorm_psi(psi,GridRep,BasisRep)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP ----------------------------------------
      TYPE (param_psi), intent(inout)          :: psi
      logical,          intent(in),   optional :: GridRep,BasisRep

!------ working variables ---------------------------------
      logical                        :: norm2GridRep,norm2BasisRep
      real (kind=Rkind)              :: temp
      real (kind=Rkind), allocatable :: tab_WeightChannels(:,:)


!----- for debuging --------------------------------------------------
      logical,parameter :: debug = .FALSE.
      !logical,parameter :: debug = .TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING renorm_psi'
        IF (present(GridRep)) write(out_unitp,*) 'norm2GridRep',GridRep
        IF (present(BasisRep)) write(out_unitp,*) 'norm2BasisRep',BasisRep
        write(out_unitp,*) 'psi'
        CALL ecri_psi(psi=psi)
      END IF
!-----------------------------------------------------------

      IF (present(GridRep)) THEN
        IF (present(BasisRep)) THEN
          norm2GridRep  = GridRep
          norm2BasisRep = BasisRep
        ELSE
          norm2GridRep  = GridRep
          norm2BasisRep = .FALSE.
        END IF
      ELSE
        IF (present(BasisRep)) THEN
          norm2BasisRep = BasisRep
          norm2GridRep  = .FALSE.
        ELSE
          IF (psi%BasisRep .AND. psi%GridRep) THEN
            norm2BasisRep = .TRUE.
            norm2GridRep  = .FALSE.
          ELSE
            norm2BasisRep = psi%BasisRep
            norm2GridRep  = psi%GridRep
          END IF
       END IF
     END IF

     IF (debug) write(out_unitp,*) 'nGridRep,nBasisRep',norm2GridRep,norm2BasisRep
      IF (norm2GridRep .AND. norm2BasisRep) THEN
        write(out_unitp,*) ' ERROR in renorm_psi'
        write(out_unitp,*) ' norm2GridRep=t and norm2BasisRep=t !'
        write(out_unitp,*) ' BasisRep,GridRep',psi%BasisRep,psi%GridRep
        STOP
      END IF

      CALL Channel_weight(tab_WeightChannels,psi,norm2GridRep,norm2BasisRep)

      IF (debug)  write(out_unitp,*) 'tab_WeightChannels : ',tab_WeightChannels

      psi%norm2 = sum(tab_WeightChannels)

      IF (debug) THEN
        write(out_unitp,*) 'norm2 : ',psi%norm2,tab_WeightChannels
      END IF

      IF (psi%norm2 .EQ. ZERO ) THEN
        write(out_unitp,*) ' ERROR in renorm_psi'
        write(out_unitp,*) ' the norm2 is zero !',psi%norm2
        STOP
      END IF
      temp = sqrt(ONE/psi%norm2)

      IF (norm2GridRep) THEN
        !- normalization of psiGridRep -------------------------
        IF (psi%cplx) THEN
          psi%CvecG(:) = psi%CvecG(:) *cmplx(temp,ZERO,kind=Rkind)
        ELSE
          psi%RvecG(:) = psi%RvecG(:) * temp
        END IF
      ELSE
        !- normalization of psiBasisRep -------------------------
        IF (psi%cplx) THEN
          psi%CvecB(:) = psi%CvecB(:) *cmplx(temp,ZERO,kind=Rkind)
        ELSE
          psi%RvecB(:) = psi%RvecB(:) * temp
        END IF
      END IF
      psi%norm2 = ONE

      IF (allocated(tab_WeightChannels)) THEN
        CALL dealloc_NParray(tab_WeightChannels,"tab_WeightChannels","renorm_psi (alloc from Channel_weight)")
      END IF

!----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'norm2 : ',psi%norm2
        write(out_unitp,*) 'END renorm_psi'
      END IF
!----------------------------------------------------------

      END SUBROUTINE renorm_psi
!=======================================================================================      

!=======================================================================================      
      SUBROUTINE renorm_psi_With_norm2(psi,GridRep,BasisRep)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP ----------------------------------------
      TYPE (param_psi), intent(inout)          :: psi
      logical,          intent(in),   optional :: GridRep,BasisRep

!------ working variables ---------------------------------
      logical                        :: norm2GridRep,norm2BasisRep
      real (kind=Rkind)              :: temp

!----- for debuging --------------------------------------------------
      logical,parameter :: debug = .FALSE.
      !logical,parameter :: debug = .TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING renorm_psi_With_norm2'
        IF (present(GridRep))  write(out_unitp,*) 'norm2GridRep',GridRep
        IF (present(BasisRep)) write(out_unitp,*) 'norm2BasisRep',BasisRep
        write(out_unitp,*) 'psi'
        CALL ecri_psi(psi=psi)
      END IF
!-----------------------------------------------------------

      IF (present(GridRep)) THEN
        IF (present(BasisRep)) THEN
          norm2GridRep  = GridRep
          norm2BasisRep = BasisRep
        ELSE
          norm2GridRep  = GridRep
          norm2BasisRep = .FALSE.
        END IF
      ELSE
        IF (present(BasisRep)) THEN
          norm2BasisRep = BasisRep
          norm2GridRep  = .FALSE.
        ELSE
          IF (psi%BasisRep .AND. psi%GridRep) THEN
            norm2BasisRep = .TRUE.
            norm2GridRep  = .FALSE.
          ELSE
            norm2BasisRep = psi%BasisRep
            norm2GridRep  = psi%GridRep
          END IF
       END IF
     END IF

     IF (debug) write(out_unitp,*) 'nGridRep,nBasisRep',norm2GridRep,norm2BasisRep
      IF (norm2GridRep .AND. norm2BasisRep) THEN
        write(out_unitp,*) ' ERROR in renorm_psi_With_norm2'
        write(out_unitp,*) ' norm2GridRep=t and norm2BasisRep=t !'
        write(out_unitp,*) ' BasisRep,GridRep',psi%BasisRep,psi%GridRep
        STOP
      END IF

      IF (debug) THEN
        write(out_unitp,*) 'norm2 : ',psi%norm2
      END IF

      IF (psi%norm2 .EQ. ZERO ) THEN
        write(out_unitp,*) ' ERROR in renorm_psi_With_norm2'
        write(out_unitp,*) ' the norm2 is zero !',psi%norm2
        STOP
      END IF
      temp = sqrt(ONE/psi%norm2)

      IF (norm2GridRep) THEN
        !- normalization of psiGridRep -------------------------
        IF (psi%cplx) THEN
          psi%CvecG(:) = psi%CvecG(:) *cmplx(temp,ZERO,kind=Rkind)
        ELSE
          psi%RvecG(:) = psi%RvecG(:) * temp
        END IF
      ELSE
        !- normalization of psiBasisRep -------------------------
        IF (psi%cplx) THEN
          psi%CvecB(:) = psi%CvecB(:) *cmplx(temp,ZERO,kind=Rkind)
        ELSE
          psi%RvecB(:) = psi%RvecB(:) * temp
        END IF
      END IF
      psi%norm2 = ONE

!----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'norm2 : ',psi%norm2
        write(out_unitp,*) 'END renorm_psi_With_norm2'
      END IF
!----------------------------------------------------------

      END SUBROUTINE renorm_psi_With_norm2

  SUBROUTINE Channel_weight(tab_WeightChannels,psi,                 &
                            GridRep,BasisRep,Dominant_Channel)
  USE mod_system
  USE mod_psi_set_alloc
  USE mod_MPI
  IMPLICIT NONE

!- variables for the WP ----------------------------------------
  real (kind=Rkind), intent(inout), allocatable :: tab_WeightChannels(:,:)
  TYPE (param_psi),  intent(inout)              :: psi
  logical,           intent(in)                 :: GridRep,BasisRep
  integer,           intent(inout), optional    :: Dominant_Channel(2)

!-- working variables ---------------------------------
  integer           :: i_qa,i_qaie
  integer           :: i_be,i_bi,i_ba,i_baie
  integer           :: ii_baie,if_baie
  real (kind=Rkind) :: WrhonD,temp,max_w
  integer           :: nb_be,nb_bi
  integer           :: iSG,iqSG,err_sub ! for SG4
  !logical           :: SG4 = .TRUE.
  TYPE (OldParam)   :: OldPara
  real (kind=Rkind) :: WeightSG



!- for debuging --------------------------------------------------
  logical,parameter :: debug = .FALSE.
  !logical,parameter :: debug = .TRUE.
!-------------------------------------------------------
  IF (debug) THEN
    write(out_unitp,*) 'BEGINNING Channel_weight'
    write(out_unitp,*) 'GridRep',GridRep
    write(out_unitp,*) 'BasisRep',BasisRep
    !write(out_unitp,*) 'psi'
    !CALL ecri_psi(psi=psi)
    CALL flush_perso(out_unitp)
  END IF
!-------------------------------------------------------

  nb_be = get_nb_be_FROM_psi(psi)
  nb_bi = get_nb_bi_FROM_psi(psi)

  IF (GridRep .AND. BasisRep) THEN
    write(out_unitp,*) ' ERROR in Channel_weight'
    write(out_unitp,*) ' GridRep=t and BasisRep=t !'
    STOP
  END IF

  IF (.NOT. allocated(tab_WeightChannels) .AND. nb_bi > 0 .AND. nb_be > 0) THEN
    CALL alloc_NParray(tab_WeightChannels,(/nb_bi,nb_be/),              &
                      "tab_WeightChannels","Channel_weight")
    tab_WeightChannels(:,:) = ZERO
  END IF


  !IF (SGtype == 4) THEN
  !  CALL Channel_weight_SG4(tab_WeightChannels,psi,                 &
  !                          GridRep,BasisRep)
  !END IF

  IF (psi%ComOp%contrac_ba_ON_HAC) THEN

    CALL Channel_weight_contracHADA(tab_WeightChannels(:,1),psi)

  ELSE IF (psi%nb_baie == psi%nb_tot) THEN

    IF (BasisRep .AND. (allocated(psi%CvecB) .OR. allocated(psi%RvecB)) ) THEN

      DO i_be=1,psi%nb_be
      DO i_bi=1,psi%nb_bi
        ii_baie = 1 + ( (i_bi-1)+ (i_be-1)*psi%nb_bi ) * psi%nb_ba
        if_baie = ii_baie -1 + psi%nb_ba

        IF (psi%cplx) THEN
          tab_WeightChannels(i_bi,i_be) =                             &
             real(dot_product(psi%CvecB(ii_baie:if_baie),             &
                              psi%CvecB(ii_baie:if_baie)) ,kind=Rkind)
        ELSE
          tab_WeightChannels(i_bi,i_be) =                               &
             dot_product(psi%RvecB(ii_baie:if_baie),                    &
                         psi%RvecB(ii_baie:if_baie))
        END IF
      END DO
      END DO

    ELSE IF (GridRep .AND. (allocated(psi%CvecG) .OR. allocated(psi%RvecG)) ) THEN

      !- initialization ----------------------------------
      tab_WeightChannels(:,:) = ZERO

      DO i_qa=1,psi%nb_qa

        !- calculation of WrhonD ------------------------------
        WrhonD = Rec_WrhonD(psi%BasisnD,i_qa)

!        IF (SG4) THEN
!          CALL get_iqSG_iSG_FROM_iq(iSG,iqSG,i_qa,psi%BasisnD%para_SGType2,OldPara,err_sub)
!          WrhonD = WrhonD * psi%BasisnD%WeightSG(iSG)
!          !write(out_unitp,*) 'i_qa,iSG',i_qa,iSG,psi%BasisnD%WeightSG(iSG)
!        END IF

        DO i_be=1,nb_be
        DO i_bi=1,nb_bi
          i_qaie = i_qa + ( (i_bi-1)+(i_be-1)*nb_bi ) * psi%nb_qa

          IF (psi%cplx) THEN
            temp = abs( psi%CvecG(i_qaie))
          ELSE
            temp = psi%RvecG(i_qaie)
          END IF
          tab_WeightChannels(i_bi,i_be) = tab_WeightChannels(i_bi,i_be) + &
                                          WrhonD *temp**2
        END DO
        END DO
      END DO

    ELSE

      write(out_unitp,*) ' ERROR in Channel_weight',' from ',MPI_id
      IF (GridRep)  write(out_unitp,*) ' impossible to calculate the weights with the Grid'
      IF (BasisRep) write(out_unitp,*) ' impossible to calculate the weights with the Basis'
      STOP
    END IF

  ELSE
    !- To deal with a spectral representation ------

    tab_WeightChannels(:,:) = ZERO

    IF (psi%cplx) THEN
      tab_WeightChannels(1,1) = real(dot_product(psi%CvecB,psi%CvecB),kind=Rkind)
    ELSE
      tab_WeightChannels(1,1) = dot_product(psi%RvecB,psi%RvecB)
    END IF
  END IF

  IF (present(Dominant_Channel)) THEN
    Dominant_Channel(:) = 1
    max_w               = ZERO
    DO i_be=1,nb_be
    DO i_bi=1,nb_bi
      IF (tab_WeightChannels(i_bi,i_be) > max_w) THEN
        max_w = tab_WeightChannels(i_bi,i_be)
        Dominant_Channel(:) = [ i_be,i_bi ]
      END IF
    END DO
    END DO
  END IF

!------------------------------------------------------
  IF (debug) THEN
    write(out_unitp,*) 'tab_WeightChannels : ',tab_WeightChannels
    write(out_unitp,*) 'END Channel_weight'
  END IF
!------------------------------------------------------

  END SUBROUTINE Channel_weight

#if(run_MPI)
!=======================================================================================  
!> calculate weight with MPI
!> be careful with the way the vector distributed 
!=======================================================================================  
  SUBROUTINE Channel_weight_MPI(tab_WeightChannels,psi,                                &
                                GridRep,BasisRep,Dominant_Channel)
  USE mod_system
  USE mod_psi_set_alloc
  USE mod_MPI
  USE mod_MPI_Aid
  IMPLICIT NONE

  TYPE(param_psi), intent(in)                   :: psi
  Real(kind=Rkind),intent(inout),allocatable    :: tab_WeightChannels(:,:)
  Integer,optional,intent(inout)                :: Dominant_Channel(2)
  Logical,         intent(in)                   :: GridRep,BasisRep

  TYPE(OldParam)                                :: OldPara
  Real(kind=Rkind)                              :: WeightSG
  Real(kind=Rkind)                              :: WrhonD
  Real(kind=Rkind)                              :: max_w
  Real(kind=Rkind)                              :: temp
  Integer                                       :: i_qa
  Integer                                       :: i_qaie
  Integer                                       :: i_be
  Integer                                       :: i_bi
  Integer                                       :: i_ba
  Integer                                       :: i_baie
  Integer                                       :: ii_baie
  Integer                                       :: if_baie
  Integer                                       :: nb_be
  Integer                                       :: nb_bi
  Integer                                       :: iSG
  Integer                                       :: iqSG

  
  nb_be=get_nb_be_FROM_psi(psi)
  nb_bi=get_nb_bi_FROM_psi(psi)

  IF(GridRep .AND. BasisRep) THEN
    write(out_unitp,*) ' ERROR in Channel_weight'
    write(out_unitp,*) ' GridRep=t and BasisRep=t !'
    STOP
  END IF

  IF(.NOT. allocated(tab_WeightChannels) .AND. nb_bi > 0 .AND. nb_be > 0) THEN
    CALL alloc_NParray(tab_WeightChannels,(/nb_bi,nb_be/),                             &
                      "tab_WeightChannels","Channel_weight")
    tab_WeightChannels(:,:) = ZERO
  END IF

  IF(psi%ComOp%contrac_ba_ON_HAC) THEN
    IF(MPI_id==0) CALL Channel_weight_contracHADA(tab_WeightChannels(:,1),psi)
  ELSE IF (psi%nb_baie==psi%nb_tot) THEN
    IF(BasisRep .AND. (allocated(psi%CvecB) .OR. allocated(psi%RvecB)) ) THEN
      nb_per_MPI=psi%nb_tot/MPI_np
      nb_rem_MPI=mod(psi%nb_tot,MPI_np) 
      bound1_MPI=MPI_id*nb_per_MPI+1+MIN(MPI_id,nb_rem_MPI)
      bound2_MPI=(MPI_id+1)*nb_per_MPI+MIN(MPI_id,nb_rem_MPI)                          &
                                      +merge(1,0,nb_rem_MPI>MPI_id)

      DO i_be=1,psi%nb_be
      DO i_bi=1,psi%nb_bi
        ii_baie=1+((i_bi-1)+(i_be-1)*psi%nb_bi) * psi%nb_ba
        if_baie=ii_baie-1+psi%nb_ba

        IF(bound2_MPI>ii_baie .AND. bound1_MPI<if_baie) THEN
          if_baie=MIN(if_baie,bound2_MPI)
          ii_baie=MAX(ii_baie,bound1_MPI)
          IF(psi%cplx) THEN
            tab_WeightChannels(i_bi,i_be)=real(dot_product(psi%CvecB(ii_baie:if_baie), &
                                               psi%CvecB(ii_baie:if_baie)),kind=Rkind)
          ELSE
            tab_WeightChannels(i_bi,i_be)=dot_product(psi%RvecB(ii_baie:if_baie),      &
                                                      psi%RvecB(ii_baie:if_baie))
          ENDIF
        ENDIF
      END DO
      END DO
      
      CALL MPI_Reduce_sum_matrix(tab_WeightChannels,1,nb_bi,1,nb_be,root_MPI)

    ELSE IF(GridRep .AND. (allocated(psi%CvecG) .OR. allocated(psi%RvecG))) THEN
      tab_WeightChannels(:,:) = ZERO
      
      nb_per_MPI=psi%nb_baie/MPI_np
      nb_rem_MPI=mod(psi%nb_baie,MPI_np) 
      bound1_MPI=MPI_id*nb_per_MPI+1+MIN(MPI_id,nb_rem_MPI)
      bound2_MPI=(MPI_id+1)*nb_per_MPI+MIN(MPI_id,nb_rem_MPI)                          &
                                      +merge(1,0,nb_rem_MPI>MPI_id)
      
      DO i_qa=1,psi%nb_qa
        WrhonD=Rec_WrhonD(psi%BasisnD,i_qa)
        DO i_be=1,nb_be
        DO i_bi=1,nb_bi
          i_qaie=i_qa+((i_bi-1)+(i_be-1)*nb_bi )*psi%nb_qa

          IF(bound2_MPI>i_qaie .AND. bound1_MPI<i_qaie) THEN            
            IF(psi%cplx) THEN
              temp=abs(psi%CvecG(i_qaie))
            ELSE
              temp=psi%RvecG(i_qaie)
            END IF
            tab_WeightChannels(i_bi,i_be)=tab_WeightChannels(i_bi,i_be)+WrhonD*temp**2
          ENDIF
        ENDDO
        ENDDO
      ENDDO
     
      CALL MPI_Reduce_sum_matrix(tab_WeightChannels,1,nb_bi,1,nb_be,root_MPI)
      
    ELSE
      write(out_unitp,*) ' ERROR in Channel_weight',' from ',MPI_id
      IF (GridRep)  write(out_unitp,*) ' impossible to calculate the weights with the Grid'
      IF (BasisRep) write(out_unitp,*) ' impossible to calculate the weights with the Basis'
      STOP
    END IF
  ELSE
    !-To deal with a spectral representation--------------------------------------------
    tab_WeightChannels(:,:)=ZERO
    
    nb_per_MPI=psi%nb_tot/MPI_np
    nb_rem_MPI=mod(psi%nb_tot,MPI_np)
    bound1_MPI=MPI_id*nb_per_MPI+1+MIN(MPI_id,nb_rem_MPI)
    bound2_MPI=(MPI_id+1)*nb_per_MPI+MIN(MPI_id,nb_rem_MPI)+merge(1,0,nb_rem_MPI>MPI_id)

    IF(psi%cplx) THEN
      temp_cplx=dot_product(psi%CvecB(bound1_MPI:bound2_MPI),                          &
                            psi%CvecB(bound1_MPI:bound2_MPI))
      CALL MPI_Reduce(temp_cplx,temp_cplx1,size1_MPI,MPI_Complex8,MPI_SUM,root_MPI,    &
                      MPI_COMM_WORLD,MPI_err)
      tab_WeightChannels(1,1)=real(temp_real1)
      !tab_WeightChannels(1,1)=real(dot_product(psi%CvecB,psi%CvecB),kind=Rkind)
    ELSE
      temp_real=dot_product(psi%RvecB(bound1_MPI:bound2_MPI),                          &
                            psi%RvecB(bound1_MPI:bound2_MPI))
      CALL MPI_Reduce(temp_real,temp_real1,size1_MPI,MPI_Real8,MPI_SUM,root_MPI,       &
                      MPI_COMM_WORLD,MPI_err)
      tab_WeightChannels(1,1)=temp_real1
      !tab_WeightChannels(1,1)=dot_product(psi%RvecB,psi%RvecB)
    ENDIF
  ENDIF

  IF(present(Dominant_Channel)) THEN
    Dominant_Channel(:)=1
    max_w              =ZERO
    DO i_be=1,nb_be
    DO i_bi=1,nb_bi
      IF(tab_WeightChannels(i_bi,i_be)>max_w) THEN
        max_w=tab_WeightChannels(i_bi,i_be)
        Dominant_Channel(:)=(/ i_be,i_bi /)
      END IF
    END DO
    END DO
  END IF

END SUBROUTINE Channel_weight_MPI
!=======================================================================================  
#endif

  SUBROUTINE Channel_weight_SG4(tab_WeightChannels,psi,GridRep,BasisRep)
  USE mod_system
  USE mod_psi_set_alloc
  USE mod_basis_BtoG_GtoB_SGType4
  IMPLICIT NONE

!- variables for the WP ----------------------------------------
  real (kind=Rkind), intent(inout), allocatable :: tab_WeightChannels(:,:)
  TYPE (param_psi),  intent(inout)              :: psi
  logical,           intent(in)                 :: GridRep,BasisRep

!-- working variables ---------------------------------

  TYPE (param_psi)          :: RCPsi(2)
  TYPE(Type_SmolyakRep)     :: SRep,WSRep ! smolyak rep for SparseGrid_type=4

  integer           :: i_qa,i_qaie
  integer           :: i_be,i_bi,i_ba,i_baie
  integer           :: ii_baie,if_baie
  real (kind=Rkind) :: WrhonD,temp,max_w
  integer           :: nb_be,nb_bi
  integer           :: iSG,iqSG,err_sub ! for SG4
  TYPE (OldParam)   :: OldPara
  real (kind=Rkind) :: WeightSG,Norm2



!- for debuging --------------------------------------------------
  logical,parameter :: debug = .FALSE.
  !logical,parameter :: debug = .TRUE.
!-------------------------------------------------------
  IF (debug) THEN
    write(out_unitp,*) 'BEGINNING Channel_weight_SG4'
    write(out_unitp,*) 'GridRep',GridRep
    write(out_unitp,*) 'BasisRep',BasisRep
    !write(out_unitp,*) 'psi'
    !CALL ecri_psi(psi=psi)
  END IF
!-------------------------------------------------------

  nb_be = get_nb_be_FROM_psi(psi)
  nb_bi = get_nb_bi_FROM_psi(psi)

  IF (psi%cplx) THEN
    CALL CplxPsi_TO_RCpsi(RCPsi,Psi)

    !For the real part

    CALL tabPackedBasis_TO_SmolyakRepBasis(SRep,RCPsi(1)%RVecB,        &
                      psi%BasisnD%tab_basisPrimSG,psi%BasisnD%nDindB,  &
                      psi%BasisnD%para_SGType2)
    !Norm2 = dot_product_SmolyakRep_Basis(SRep,SRep,psi%BasisnD%WeightSG)

    CALL BSmolyakRep_TO_GSmolyakRep(SRep,                               &
                  psi%BasisnD%para_SGType2%nDind_SmolyakRep%Tab_nDval,  &
                  psi%BasisnD%tab_basisPrimSG,psi%BasisnD%para_SGType2%nb0)
    WSRep = Set_weight_TO_SmolyakRep(                                   &
                  psi%BasisnD%para_SGType2%nDind_SmolyakRep%Tab_nDval,  &
                  psi%BasisnD%tab_basisPrimSG)

    Norm2 = dot_product_SmolyakRep_Grid(SRep,SRep,WSRep,psi%BasisnD%WeightSG)
    !CALL Write_SmolyakRep(SRep)

    !For the imaginary part
    CALL tabPackedBasis_TO_SmolyakRepBasis(SRep,RCPsi(2)%RVecB,        &
          psi%BasisnD%tab_basisPrimSG,psi%BasisnD%nDindB,psi%BasisnD%para_SGType2)
    Norm2 = Norm2 + dot_product_SmolyakRep_Basis(SRep,SRep,psi%BasisnD%WeightSG)
    !CALL Write_SmolyakRep(SRep)

   ELSE
    CALL tabPackedBasis_TO_SmolyakRepBasis(SRep,Psi%RVecB,        &
          psi%BasisnD%tab_basisPrimSG,psi%BasisnD%nDindB,psi%BasisnD%para_SGType2)
    !CALL Write_SmolyakRep(SRep)
    Norm2 = dot_product_SmolyakRep_Basis(SRep,SRep,psi%BasisnD%WeightSG)
  END IF

  write(out_unitp,*) 'Norm2_SG4',Norm2

!------------------------------------------------------
  IF (debug) THEN
    write(out_unitp,*) 'END Channel_weight_SG4'
  END IF
!------------------------------------------------------

  END SUBROUTINE Channel_weight_SG4
      SUBROUTINE Channel_weight_contracHADA(w_harm,psi)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE

       TYPE (param_psi)   :: psi
       real (kind=Rkind) :: w_harm(psi%nb_bi)

       integer       :: ih,ihk,k


!----- for debuging --------------------------------------------------
      logical, parameter :: debug=.FALSE.
      !logical, parameter :: debug=.TRUE.
!-----------------------------------------------------------
       IF (debug) THEN
         write(out_unitp,*) 'BEGINNING Channel_weight_contracHADA'
         write(out_unitp,*) 'nb_bi,nb_ai',psi%nb_bi
       END IF
!-----------------------------------------------------------


!        weight on the harmonic states
         DO ih=1,psi%nb_bi
           ihk = sum(psi%ComOp%nb_ba_ON_HAC(1:ih-1))
           w_harm(ih) = ZERO
           DO k=1,psi%ComOp%nb_ba_ON_HAC(ih)
             ihk = ihk + 1
             IF (psi%cplx) THEN
               w_harm(ih) = w_harm(ih) + abs(psi%CvecB(ihk))**2
             ELSE
               w_harm(ih) = w_harm(ih) + psi%RvecB(ihk)**2
             END IF
           END DO
         END DO

!----------------------------------------------------------
        IF (debug) THEN
          write(out_unitp,*) 'END Channel_weight_contracHADA'
        END IF
!----------------------------------------------------------


      end subroutine Channel_weight_contracHADA

!=======================================================================================
!> MPI version of Channel_weight_contracADA
!=======================================================================================
!SUBROUTINE Channel_weight_contracADA_MPI(w_harm,psi)
!  USE mod_system
!  USE mod_psi_set_alloc
!  USE mod_MPI
!  IMPLICIT NONE
!
!  TYPE(param_psi)                                       :: psi
!  Real(kind=Rkind)                                      :: w_harm(psi%nb_bi)
!
!  Integer                                               :: ih
!  Integer                                               :: ihk
!  Integer                                               :: k
!
!  ! weight on the harmonic states
!  DO ih=1,psi%nb_bi
!    ihk=sum(psi%ComOp%nb_ba_ON_HAC(1:ih-1))
!    w_harm(ih)=ZERO
!    DO k=1,psi%ComOp%nb_ba_ON_HAC(ih)
!      ihk=ihk+1
!      write(*,*) 'ih,ihk check',ih,ihk
!      IF(psi%cplx) THEN
!        w_harm(ih)=w_harm(ih)+abs(psi%CvecB(ihk))**2
!      ELSE
!        w_harm(ih)=w_harm(ih)+psi%RvecB(ihk)**2
!      ENDIF
!    ENDDO
!  ENDDO
!
!END SUBROUTINE Channel_weight_contracADA_MPI

!==============================================================
!
!      calc_DM
!
!==============================================================
      SUBROUTINE calc_DM(psi,max_1D,T,info,print_DM)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE


!----- variables for the WP propagation ----------------------------
      TYPE (param_psi)   :: psi


      complex (kind=Rkind),allocatable :: DM(:,:),DM2(:,:)
      complex (kind=Rkind),allocatable :: DM_v1(:,:)
      complex (kind=Rkind),allocatable :: DM2_v1(:,:)
      real (kind=Rkind),allocatable    :: weight(:)
      complex (kind=Rkind) :: tr,tr2

      real (kind=Rkind)    :: T ! time
      logical          :: print_DM
      character (len=*)    :: info

      integer          :: nb_ba
      integer          :: ib,ibie
      integer          :: max_1D,max_print

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub='calc_DM'
      logical, parameter :: debug =.FALSE.
!     logical, parameter :: debug =.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'nb_tot',psi%nb_tot
        write(out_unitp,*) 'nb_bi,nb_be',psi%nb_bi,psi%nb_be
        write(out_unitp,*) 'nb_bie',psi%nb_bi*psi%nb_be
      END IF
!-----------------------------------------------------------

      IF (print_DM) THEN
        max_print = min(50,psi%nb_tot)
        CALL alloc_NParray(weight,(/psi%nb_tot/),"weight",name_sub)
        weight(:) = real(conjg(psi%CvecB)*psi%CvecB,kind=Rkind)
!       write(out_unitp,*) 'T weight_tot',T,weight(1:max_print)
        write(out_unitp,'(a,f12.1,1x,a,50(1x,f8.6))')                           &
                 'T weight_tot ',T,trim(info),weight(1:max_print)
        CALL dealloc_NParray(weight,"weight",name_sub)
      END IF
      IF (psi%nb_baie /= psi%nb_tot) THEN
        CALL alloc_NParray(DM ,(/psi%nb_tot,psi%nb_tot/),"DM" ,name_sub)
        CALL alloc_NParray(DM2,(/psi%nb_tot,psi%nb_tot/),"DM2",name_sub)

        DM(:,:) = CZERO
        DM(:,:) = matmul(                                             &
                conjg(reshape(psi%CvecB,(/psi%nb_tot,1/)) ),          &
                      reshape(psi%CvecB,(/1,psi%nb_tot/))  )

        DM2 = matmul(DM,DM)

        tr  = CZERO
        tr2 = CZERO
        DO  ibie=1,psi%nb_tot
          tr = tr + DM(ibie,ibie)
          tr2 = tr2 + DM2(ibie,ibie)
        END DO
        write(out_unitp,*) 'T tr(DM),tr(DM2)',T,abs(tr),abs(tr2)
        CALL dealloc_NParray(DM ,"DM" ,name_sub)
        CALL dealloc_NParray(DM2,"DM2",name_sub)
      END IF

      IF (psi%nb_baie == psi%nb_tot .AND. psi%nb_bi*psi%nb_be > 1) THEN
        nb_ba = psi%nb_ba
        CALL alloc_NParray(DM_v1 ,(/nb_ba,nb_ba/),"DM_v1",name_sub)
        CALL alloc_NParray(DM2_v1,(/nb_ba,nb_ba/),"DM2_v1",name_sub)

        DM_v1(:,:) = matmul(                                            &
                conjg(reshape(psi%CvecB,(/nb_ba,1/)) ),                 &
                      reshape(psi%CvecB,(/1,nb_ba/))  )
!       DM_v1(:,:) = DM(1:psi%nb_ba,1:psi%nb_ba)
        DM2_v1 = matmul(DM_v1,DM_v1)
        tr  = CZERO
        tr2 = CZERO
        DO  ib=1,psi%nb_ba
          tr = tr + DM_v1(ib,ib)
          tr2 = tr2 + DM2_v1(ib,ib)
        END DO
        write(out_unitp,*) 'T v1 tr(DM),tr(DM2)',T,abs(tr),abs(tr2)

        CALL dealloc_NParray(DM_v1 ,"DM_v1" ,name_sub)
        CALL dealloc_NParray(DM2_v1,"DM2_v1",name_sub)
      END IF

!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!-----------------------------------------------------------



      END SUBROUTINE calc_DM

!==============================================================
!
!      calc_nDTk(psi)
!
!==============================================================
      SUBROUTINE calc_nDTk(psi,T)
      USE mod_system
      USE mod_psi_set_alloc
      IMPLICIT NONE

!----- variables for the WP propagation ----------------------------
      TYPE (param_psi)   :: psi


      real (kind=Rkind)    :: T ! time

      integer          :: k
      integer          :: iei,ib,ibie,nb_bie

      real (kind=Rkind),allocatable :: w_ei(:)

      complex (kind=Rkind),allocatable :: Ek_ei(:)
      complex (kind=Rkind),allocatable :: Ck_ei(:),Sk_ei(:)
      complex (kind=Rkind)    :: a

!----- for debuging --------------------------------------------------
      character (len=*), parameter :: name_sub='calc_nDTk'
      integer :: err_mem,memory
      logical, parameter :: debug =.FALSE.
!     logical, parameter :: debug =.TRUE.
!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'BEGINNING ',name_sub
        write(out_unitp,*) 'nb_bi,nb_be',psi%nb_bi,psi%nb_be
      END IF
!-----------------------------------------------------------

      IF (psi%nb_baie /= psi%nb_tot) RETURN


      nb_bie = psi%nb_bi*psi%nb_be
      CALL alloc_NParray(w_ei,(/nb_bie/),"w_ei",name_sub)
      CALL alloc_NParray(Ek_ei,(/nb_bie/),"Ek_ei",name_sub)
      CALL alloc_NParray(Ck_ei,(/nb_bie/),"Ck_ei",name_sub)
      CALL alloc_NParray(Sk_ei,(/nb_bie/),"Sk_ei",name_sub)

      DO ib=1,psi%nb_ba
        k = int(ib/2)
        DO iei=1,nb_bie
          ibie = ib + (iei-1) * psi%nb_ba

          IF (psi%cplx) a = psi%CvecB(ibie)
          IF (.NOT. psi%cplx) a=cmplx(psi%RvecB(ibie),ZERO,kind=Rkind)
          IF (mod(ib-1,2) == 0) THEN
            Ck_ei(iei) = a
          ELSE
            Sk_ei(iei) = a
          END IF
        END DO
        IF (mod(ib-1,2) == 0) THEN

          Ek_ei = CHALF*(Ck_ei-EYE*Sk_ei)
          DO iei=1,nb_bie
            w_ei(iei) = abs(Ek_ei(iei))**2
          END DO
          write(998,*) 'T,+k',T,k,w_ei

          Ek_ei = CHALF*(Ck_ei+EYE*Sk_ei)
          DO iei=1,nb_bie
            w_ei(iei) = abs(Ek_ei(iei))**2
          END DO
          write(999,*) 'T,-k',T,k,w_ei

        END IF
      END DO
      write(998,*)
      write(999,*)
      CALL flush_perso(998)
      CALL flush_perso(999)

      CALL dealloc_NParray(w_ei,"w_ei",name_sub)
      CALL dealloc_NParray(Ek_ei,"Ek_ei",name_sub)
      CALL dealloc_NParray(Ck_ei,"Ck_ei",name_sub)
      CALL dealloc_NParray(Sk_ei,"Sk_ei",name_sub)

!-----------------------------------------------------------
      IF (debug) THEN
        write(out_unitp,*) 'END ',name_sub
      END IF
!-----------------------------------------------------------



      END SUBROUTINE calc_nDTk

END MODULE mod_ana_psi

