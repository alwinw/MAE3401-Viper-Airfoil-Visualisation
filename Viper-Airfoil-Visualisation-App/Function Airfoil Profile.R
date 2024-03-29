#----------------------------
#--- Functions for Airfoil Calculations
#============================

#--- Transform a set of (x,y) based on an AoA (in deg) ----
AoATransform <- function(data, AoA) {
  # Assumes X is column 1 and Y is column 2
  # Store the input data
  odata <- data
  ocolnames <- colnames(data)
  colnames(data[c(1,2)]) <- c("x", "y")
  # Apply the transformation
  data <- select(data, x, y) %>%
    mutate(
      r = sqrt(x^2 + y^2),
      theta = atan(y/x),
      theta = ifelse(is.na(theta),0,theta),
      theta = ifelse(x < 0, theta + pi, theta),
      theta = theta - AoA*pi/180,
      x = r*cos(theta),
      y = r*sin(theta)
    ) %>%
    select(x, y)
  # Re-combine the new data with the old data and restore colnames
  odata[c(1,2)] = data
  colnames(odata) <- ocolnames
  return(odata)
}

#--- Surface Coordinates for a NACA 4 digit airfoil ----
AirfoilCurve <- function(x = 0, out = "all") {
  # Test if x is within range
  on = ifelse(x >= a & x <= (a + c), 1, 0) # allows for root-finding
  # Determine the camber line yc
  yc = ifelse(x < p * c + a, 
    m/p^2 * (2*p*((x-a)/c) - ((x-a)/c)^2),
    m/(1-p)^2  * (1 - 2*p + 2*p*((x-a)/c) - ((x-a)/c)^2)
  )
  # Determine the gradient of the camber line dycdx
  dycdx = ifelse(x < p * c + a,
    2*m/p^2 * (p - (x-a)/c),
    2*m/(1-p)^2 * (p - (x-a)/c)
  )
  # Determine the magnitude and direction of the thickness
  theta = atan(dycdx)
  yt = 5*t*(0.2969*sqrt(abs((x-a)/c)) - 0.1260*((x-a)/c) - 0.3516*((x-a)/c)^2 +
              0.2843*((x-a)/c)^3 - 0.1036*((x-a)/c)^4)
  # Add the thickness to the camber line
  xU = x - yt*sin(theta)
  yU = yc + yt*cos(theta)
  xL = x + yt*sin(theta)
  yL = yc - yt*cos(theta)
  # Output depending on the Out parameter
  if(out == "all")
    summary = data.frame(x, yc, dycdx, theta, yt,  xU, yU,  xL, yL)
  else if(out == "coord")
    summary = data.frame(x, xU, yU, xL, yL)
  else if (out == "upper")
    summary = data.frame(x = xU, y = yU)
  else if (out == "lower")
    summary = data.frame(x = xL, y = yL)
  # Return the output
  return(summary * on)
}

#--- Outputs Airfoil Points into (x,y) columns and AoA transform for plotting ----
AirfoilCoord <- function(xmin = a, xmax = c + a, AoA = 0, res = 100) {
  # Cluster points around LE and TE
  xvec = abs(a) * sin(seq(xmin, xmax, length.out = res)*pi/c)
  # Generate coordinates in a tidy format
  coord = AirfoilCurve(xvec, out = "coord") %>%
    rename(xO = x) %>%
    gather(key, value, -xO) %>%
    mutate(coord = substr(key,1,1), surf = substr(key, 2,2)) %>%
    select(-key) %>%
    spread(coord, value) %>%
    mutate(surf = factor(surf, levels = c("U", "L"))) %>%
    arrange(surf, xO*ifelse(surf=="U", 1, -1)) %>%
    select(x, y, surf)
  coord = AoATransform(coord, AoA = AoA)
  return(coord)
}

#--- Function for better sampling of points ----
AirfoilSamp <- function(xvec, del = c*8e-6, cylinder = FALSE) {
  # xvec = seq(a, a+c, by = 0.01)
  # Sample according to a cubic function
  xvec = -2*a/c^3 * (xvec - a)^3 + a
  # Add extra x values for interpolation
  if (cylinder != FALSE & xvec[1] == a) {
    # Determine the number of points from -theta_c to theta_c
    xadd = seq(-0.0001, -thetac,  
               length.out = ceiling(length(xvec[xvec < xsamp])/2 + 1))
    xadd = xadd[xadd != -thetac]
    # 'encode it' and combine
    xadd = a - abs(a) + xadd
    # Return the result depending on what's required
    if (cylinder == TRUE)
      xvec = c(xadd, xvec)
    if (cylinder == "only")
      xvec = xadd
    }
    
  # Remove any unecessary LE
  # LE = match(a, xvec)
  # if (xvec[LE] == a)
  #   xvec = xvec[-LE]
  
  # xvec[LE] = a - sign(a)*abs(a)*del
  # if (!is.na(LE) & xvec[LE] > xvec[LE +1])
  #   xvec = xvec[-LE]

  xvec = xvec[xvec != a]
  
  # Adjust the TE value
  if (xvec[length(xvec)] == a + c)
    xvec[length(xvec)] = a + c - sign(a + c)*abs(a + c)*del

  return(xvec)
}

#--- Find the xL or XU value for a given x ----
Airfoilx <- function(xO,  surf = "upper", tol = 1e-9, out = "x") {
  # Use the rooting finding in {stats} to find the root
  rootfind <- uniroot(function(x) AirfoilCurve(x, out = surf)$x - xO,
          lower = a, upper = a + c,
          tol = tol)
  if(out == "x")
    return(rootfind$root)
  else if(out ==  "all")
    return(rootfind)
  else if(out == "str")
    return(str(rootfind))
}

#--- Helper functions for finding the gradient ----
AirfoilGradNACA <- function(xO, surf, del) {
  # Determine the value of x for xO on the airfoil and neighbours
  x = Airfoilx(xO, surf = surf)
  x = c(x-del, x, x + del)
  # Determine the values
  surfval = AirfoilCurve(x, out = surf)
  
  # Estimate the gradients
  surfval <- mutate(surfval,
                    dydx = (y - lag(y, 1)) / (x - lag(x, 1)),
                    dydxave = (dydx + lag(dydx, 1)) / 2)
  dydx = surfval$dydxave[3]
  
  # Determine normal and tagential equations for output
  out <- list(out = data.frame(
    surf = surf,
    eq = c("tan", "norm"),
    x = surfval$x[2],
    y = surfval$y[2],
    m = c(dydx, -1/dydx)) %>%
    mutate(c = -m*x + y)
  )
  return(out)
}

AirfoilGradCyl <- function(xO, surf, del) {
  thetaO = xO - a + abs(a)
  thetaO = ifelse(surf == "upper", 1, -1) * thetaO
  mN = tan(thetaO)
  
  # Generate the output
  out <- list(out = data.frame(
    surf = surf,
    eq = c("tan", "norm"),
    x = xc -r*cos(thetaO),
    y = yc -r*sin(thetaO),
    m = c(-1/mN, mN)) %>%
    mutate(c = -m*x + y)
  )
  return(out)
}

#--- Determine the gradient of the airfoil at x ----
AirfoilGrads <- function(xO, surf = "upper", del = c*1e-8, out = "all") {
  # out <- ifelse(xO < a - sign(a)*abs(a)*del*100,
  #               AirfoilGradCyl(xO, surf, del),
  #               AirfoilGradNACA(xO, surf, del))
  out <- ifelse(xO < a,
                AirfoilGradCyl(xO, surf, del),
                AirfoilGradNACA(xO, surf, del))
  out <- out[[1]]
  return(out)
}

#--- Generate (x,y) lines from the surface ----
AirfoilLineGen <- function(xO, AoA = 0, surf = "upper", eq = "norm", 
                           focusdist = 0.5, totaldist = 20, len = 51) {
  # NOTE: tangent is broken, won't work!!
  # focusdist and totaldist are lenghts ALONG the line
  gradint <- AirfoilGrads(xO, surf = surf)
  # Using the graident-intercepts, determine the range of points
  #   (corrected for gradient direction & upper vs lower surface)
  gradint <- gradint %>%
    filter(surf == get("surf") & eq == get("eq")) %>%
    mutate(focusdist = focusdist, len = len) %>%
    mutate(xfocusdist = sign(m) * focusdist/sqrt(1+m^2) * ifelse(surf=="upper",1,-1),
           xtotaldist = totaldist/focusdist * xfocusdist) %>%
    mutate(xfocus = x + xfocusdist, yfocus = y + xfocusdist*m) %>%
    mutate(xmax = x + xtotaldist, ymax = y + xtotaldist*m)
  # Generate the points (x,y)
  x = with(gradint, c(seq(x, xfocus, length.out = len), seq(xfocus, xmax, length.out = len*4)))
  y = with(gradint, c(seq(y, yfocus, length.out = len), seq(yfocus, ymax, length.out = len*4)))
  lvec = data.frame(x, y)
  # Transform the points based on the AoA supplied
  lvec = AoATransform(distinct(lvec), AoA)
  return(lvec)
}
