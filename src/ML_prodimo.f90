module ML_prodimo

  use prodimo
  use constantes

  implicit none

  private

   real(kind=dp), dimension(:,:), allocatable :: J_ML
   real(kind=dp), dimension(:,:), allocatable :: feature_Tgas
   real(kind=dp), dimension(:,:), allocatable :: feature_abundance

contains

  subroutine init_ML()

    integer :: alloc_status

    ! Todo : check or force wavelength bins

    alloc_status = 0
    allocate(J_ML(n_cells,n_lambda), stat=alloc_status)
    if (alloc_status /= 0) call error("Allocation J_ML")

    allocate(feature_Tgas(n_cells,51), stat=alloc_status)
    if (alloc_status /= 0) call error("Allocation feature_Tgas")
    
    allocate(feature_abundance(n_cells,52), stat=alloc_status)
    if (alloc_status /= 0) call error("Allocation feature_abundance")

    ! Todo : we also need to allocate an array for the interface
    ! n_cells x 52 features

    return

  end subroutine init_ML

  subroutine save_J_ML(lambda, lISM)
    ! sauvegarde le champ de radiation pour ProDiMo
    ! avant et apres le calcul du champ ISM

    integer, intent(in) :: lambda
    logical, intent(in) :: lISM

    integer :: icell
    real(kind=dp) :: n_photons_envoyes, energie_photon, facteur
    real :: wl

    if (.not.lISM) then
       ! Step2
       n_photons_envoyes = sum(n_phot_envoyes(lambda,:))
       energie_photon = hp * c_light**2 / 2. * (E_stars(lambda) + E_disk(lambda)) / n_photons_envoyes &
            * tab_lambda(lambda) * 1.0e-6  !lambda.F_lambda  ! ICI

       do icell=1, n_cells
          facteur = energie_photon / volume(icell)
          J_ML(icell,lambda) = facteur * sum(xJ_abs(icell,lambda,:))
       enddo

       ! reset for ISM radiation
       xJ_abs(:,lambda,:) = 0.0
       xN_abs(:,lambda,:) = 0.0
    else ! Champs ISM
       n_photons_envoyes = sum(n_phot_envoyes_ISM(lambda,:))

       wl = tab_lambda(lambda) * 1e-6
       energie_photon = (chi_ISM * 1.71 * Wdil * Blambda(wl,T_ISM_stars) + Blambda(wl,TCmb)) * wl & !lambda.F_lambda
            * (4.*pi*(R_ISM*Rmax)**2) / n_photons_envoyes / pi  ! ici

       do icell=1, n_cells
          facteur = energie_photon / volume(icell)
          J_ML(icell,lambda) =  J_ML(icell,lambda) +  facteur * sum(xJ_abs(icell,lambda,:))
       enddo
    endif

    return

  end subroutine save_J_ML
  
  subroutine xgb_compute_fea()
  
    use output, only : compute_CD
    
    real, dimension(n_cells,0:3) :: N_grains
    logical, dimension(n_grains_tot) :: mask_not_PAH

    integer, parameter :: n_directions = 4
    real, dimension(n_cells,n_directions) :: CD

    real(kind=dp) :: N
    integer :: icell
    
    !--- Grille
    !r_grid(:)
    !z_grid(:)


    !--- Dust temperature
    !Temperature(:)

    !--- Champ de radiation
    !J_ML(:,:)


    !--- Densite de gaz
    !densite_gaz(:) * masse_mol_gaz / m3_to_cm3 ! g.cm^-3


    !--- Moments de la distribution de grain
    mask_not_PAH(:) = .not.grain(:)%is_PAH
    do icell=1, n_cells
       N = sum(densite_pouss(:,icell),mask=mask_not_PAH)
       N_grains(icell,0) = N
       if (N > 0) then
          N_grains(icell,1) = sum(densite_pouss(:,icell) * r_grain(:),mask=mask_not_PAH) / N
          N_grains(icell,2) = sum(densite_pouss(:,icell) * r_grain(:)**2,mask=mask_not_PAH) / N
          N_grains(icell,3) = sum(densite_pouss(:,icell) * r_grain(:)**3,mask=mask_not_PAH) / N
       else
          N_grains(icell,1) = 0.0
          N_grains(icell,2) = 0.0
          N_grains(icell,3) = 0.0
       endif
    enddo
    ! part.cm^-3 --> part.m^-3
    N_grains(:,0) = N_grains(:,0) /  (cm_to_m**3)

    !--- Column density
    call compute_CD(CD)

    feature_Tgas(:,1) = r_grid
    feature_Tgas(:,2) = z_grid
    feature_Tgas(:,3) = temperature
    feature_Tgas(:,4) = densite_gaz(:) * masse_mol_gaz / m3_to_cm3 ! g.cm^3
    feature_Tgas(:,5:43) = J_ML
    feature_Tgas(:,44:47) = N_grains
    feature_Tgas(:,48:51) = CD
    feature_Tgas = log10(feature_Tgas)
    
  end subroutine xgb_compute_fea 

  subroutine xgb_predict_Tgas()
    
    integer :: out_len
    
    ! Predict Tgas
    ! ---> Tcin()
    
    call predict("model_Tgas", feature_Tgas, size(feature_Tgas,1), 51, Tcin, out_len) ! à terme remplacer par un Path

    feature_abundance(:,1:51) = feature_Tgas
    feature_abundance(:,52) = Tcin

    ! Predict abundance
    ! ---> tab_abundance()

    return

  end subroutine xgb_predict_Tgas
  
  subroutine xgb_predict_abundance(molecule)

     integer :: out_len
     character(len = 10), intent(in) :: molecule
     
     ! Predict abundance
     ! ---> tab_abundance()
     
     ! TODO : Some molecules are gave with in differents units do aptation
     
     call predict("model_" // molecule, feature_abundance, size(feature_abundance,1), 52, tab_abundance, out_len)
     
  end subroutine xgb_predict_abundance
     
end module ML_prodimo
