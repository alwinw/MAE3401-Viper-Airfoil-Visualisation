#----------------------------
#--- Functions for Interpolations
#============================

#--- Interpolate the original mesh into a rectangular grid ----

#--- Interpolate the original mesh along a path (e.g. airfoil) ----
InterpPath <- function(omesh, 
                       xO = NA, AoA = 0, surf = "upper", eq = "norm", 
                       focusdist = 0.5, totaldist = 20, len = 51,
                       lvec = NA, 
                       varnames = c("U", "V", "P", "vort_xy_plane"),
                       linear = TRUE) {
  # Determine if lvec needs to be calcuated
  if(is.na(lvec))
    lvec = AirfoilLineGen(xO, AoA, surf, eq, focusdist, totaldist, len)
  # Loop through each variable to interpolate
  lmesh <- lvec
  for (var in varnames) {
    lmeshv <- suppressWarnings(
      as.data.frame(interpp(x = omesh$x, y = omesh$y, z = omesh[[var]],
                            xo = lvec$x, yo = lvec$y,
                            linear = linear,
                            extrap = TRUE)))
    lmesh <- cbind(lmesh, lmeshv[3])
  }
  # Give the columns meaningful names
  colnames(lmesh) <- c(colnames(lvec), varnames)
  return(lmesh)
}

#--- Interpolate the original mesh along a straight line ----
InterpPerpLine <- function(omesh, 
                       xO = NA, AoA = 0, surf = "upper", eq = "norm", 
                       focusdist = 0.5, totaldist = 20, len = 51,
                       lvec = NA, 
                       varnames = c("U", "V", "P", "vort_xy_plane"),
                       linear = TRUE) {
  # Generate the mesh along the path
  lmesh <- InterpPath(omesh, 
                      xO, AoA, surf, eq, focusdist, totaldist, len,
                      lvec, varnames, linear)
  # Caculate the gradient and angle of the line
  del = tail(lmesh,1) - head(lmesh, 1)
  grad = del[[2]]/del[[1]]
  theta = atan(grad)
  ydir = sign(del[[2]])
  # Caculate the free stream conditions along the line (U = 1, V = 0)
  Um = abs(sin(theta))
  Vm = sign(m) * cos(theta)   ## NEEDS TO BE CHECKED----
  # The origin points for the line to calculate distance
  xo = lmesh[1,1]
  yo = lmesh[1,2]
  # Calculate the distance, Udash, Vdash and fraction of the free stream
  lmesh <- lmesh  %>%
    mutate(dist = sqrt((x-xo)^2 + (y-yo)^2),
           Um = Um,
           Vm = Vm) %>%
    mutate(Udash = sign(theta) * (sin(theta) * U - cos(theta) * V),
           Vdash = ifelse(surf == "upper", 1, -1) * sign(theta) * (cos(theta) * U + sin(theta) * V)) %>% ## NEEDS TO BE FIXED ----
    mutate(Udash = ifelse(surf == "upper" & ydir == -1, -1, 1) * ifelse(surf == "lower" & ydir == 1, -1, 1) * Udash,
           Vdash = ifelse(surf == "upper" & ydir == -1, -1, 1) * ifelse(surf == "lower" & ydir == 1, -1, 1) * Vdash) %>%
    mutate(percentUm = Udash/Um * 100,
           percentVm = Vdash/Vm * 100)
  return(lmesh)
}
