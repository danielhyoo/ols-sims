library("tidyverse")

# Combine standard deviation and corrlation with covariance
sdcor2cov <- function(s, r = diag(length(s))) {
  s <- diag(s, nrow = length(s), ncol = length(s))
  s %*% r %*% s
}

# Generate a data frame with multivariate normal variables
mvnorm_df <- function(n, mu, Sigma = diag(length(mu)), empirical = TRUE) {
  as_tibble(MASS::mvrnorm(n, mu = mu, Sigma = Sigma, empirical = empirical))
}

#' Find regression standard error to produce a given R-squared
#'
#' @description For a normal linear model, given a sample X and population beta,
#' find the regression standard deviation to produce the desired R-squared.
#'
#' @param y The expected value of Y
#' @param r2 The desired R^2
#' @return The regression standard deviation to produce that R^2.
#' @export
r2_to_sigma <- function(y, r2) {
  # Var(Y) = E(Var(Y|X)) + Var(E(Y|X))
  ssm <- sum((y - mean(y)) ^ 2)
  sse <- (1 - r2) / r2 * ssm
  # return sigma (assume population n)
  sqrt(sse / n)
}

n <- 100
k <- 5
mu <- rep(0, k)
beta <- c(0, rep(1, k))
X <- mvnorm_df(n, rep(0, k), diag(k))
E_y <- cbind(1, as.matrix(X)) %*% beta
sigma_y <- r2_to_sigma(E_y, 0.5)


# Simulate from linear model model
# Y ~ N(XB, sigma2), with fixed X
# Note: use a vector of sigma for
sim_lm_normal <- function(.data, beta, sigma, ov = NULL) {
  n <- nrow(X)
  # Generate the formula to estimate (potentially removing variables)
  f <- paste0("y", "~", paste0(setdiff(names(.data), ov), collapse = "+"))
  # generate and add y variable
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- rnorm(n, mean = 0, sd = sigma)
  .data$y <- E_y + eps
  eval(bquote(lm(.(f), data = .data, model.frame = FALSE, y = FALSE, X = FALSE)))
}

# Simulate from linear model model
# random X uncorrelated with Y
sim_lm_random_X <- function(n, mu_X, Sigma_X, beta, sigma_y, ov = NULL) {
  n <- nrow(X)
  .data <- mvnorm_df(n, mu = mu_X, Sigma = Sigma_X)
  # Generate the formula to estimate (potentially removing variables)
  f <- paste0("y", "~", paste0(setdiff(names(.data), ov), collapse = "+"))
  # generate and add y variable
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- rnorm(n, mean = 0, sd = sigma)
  .data$y <- E_y + eps
  eval(bquote(lm(.(f), data = .data, model.frame = FALSE, y = FALSE, X = FALSE)))
}

# Simulate from student t error and estimate with OLS
sim_lm_t <- function(.data, beta, sigma, df = 3, ov = NULL) {
  # if ov is not specified use the last variable in .datas
  ov <- ov %||% names(.data)[ncol(.data)]
  n <- nrow(X)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- rt(n, df = df) * sigma
  .data$y <- E_y + eps
  # generate linear regression formula - which excludes the
  # omitted variable
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}

#  Simulate from skewed Student-t distribution
# df = degrees of freedom as in Student-t
# xi = skewnewss. (0, 1) = left skew, 1 = symmetric. > 1 = right skew
sim_skewt <- function(.data, beta, sigma, df = 5, skew = 1.5, ov = NULL) {
  # if ov is not specified use the last variable in .datas
  ov <- ov %||% names(.data)[ncol(.data)]
  n <- nrow(X)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- fGarch::rsstd(n, mean = 0, sd = sigma, nu = df, xi = skew)
  .data$y <- E_y + eps
  # generate linear regression formula - which excludes the
  # omitted variable
  f <- paste0("y", "~", paste0(setdiff(names(.data), ov), collapse = "+"))
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}

# Simulate clustered lm model
sim_cluster <- function(.data, groups, beta, sigma_y, sigma_g) {
  n <- nrow(X)
  g <- cut_number(seq_len(n), groups, labels = false)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  # individual random error
  eps <- rnorm(n, mean = 0, sd = sigma_y)
  # group error
  nu <- rnorm(groups, mean = 0, sd = sigma_g)
  .data$y <- E_y + nu[g] + eps
  # omitted variable
  f <- paste0("y", "~", paste0(names(.data), collapse = "+"))
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}

sim_armax <- function(.data, groups, beta, sigma_y, ar = NULL, ma = NULL) {
  n <- nrow(X)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  # ARMA
  eps <- arima.sim(list(ar = ar, ma = ma), n, sd = sigma_y)
  # group error
  .data$y <- E_y + eps
  # omitted variable
  f <- paste0("y", "~", paste0(names(.data), collapse = "+"))
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}

sim_measure_error <- function(.data, beta, sigma_y, rho) {
  n <- nrow(X)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- rnorm(n, mean = 0, sd = sigma_y)
  y <- E_y + eps
  # add measurement error before the regression
  # Need to add *after* y is generated
  # easier to do this without adding rho
  for (i in seq_along(rho)) {
    # scale of measurement error
    # rho = delta^2 /  (delta^2 + var(x)^2)
    # rho = 0 is no measurement error
    # rho = 1 is all measurement error
    delta <- sqrt(rho[[i]] / (1 - rho[[i]]) * var[[.data[[i]]]])
    .data[[i]] <- .data[[i]] + rnorm(n, mean = 0, sd = delta)
  }
  # add y to the data frame
  .data$y <- y
  f <- paste0("y", "~", paste0(names(.data), collapse = "+"))
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}

# sim truncate y
sim_select_y <- function(.data, beta, sigma_y, ub = 1, lb = 0) {
  n <- nrow(X)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- rnorm(n, mean = 0, sd = sigma_y)
  y <- E_y + eps
  # add y to the data frame
  .data$y <- y
  # remove all y values < quantile or greater than quantile
  .data <- dplyr::filter(.data,
                         y >= quantile(y, lb),
                         y <= quantile(y, ub))
  f <- paste0("y", "~", paste0(names(.data), collapse = "+"))
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}

# sim truncate y
sim_select_x <- function(.data, beta, sigma_y, ub = 1, lb = 0) {
  n <- nrow(X)
  E_y <- cbind(1, as.matrix(.data)) %*% beta
  eps <- rnorm(n, mean = 0, sd = sigma_y)
  y <- E_y + eps
  # remove all x values < quantile or greater than quantile
  tokeep <- rep(TRUE, n)
  # but calculate all bounds prior to filtering
  if (length(ub) == 1) {
    ub <- rep(ub, ncol(.data))
  }
  if (length(lb) == 1) {
    lb <- rep(lb, ncol(.data))
  }
  for (i in seq_along(ub)) {
    tokeep <- (tokeep &
               .data[[i]] >= quantile(.data[[i]], lb) &
               .data[[i]] <= quantile(.data[[i]], ub))
  }
  # remove bad rows
  .data <- .data[keep, , drop = FALSE]
  # add y to the data frame
  .data$y <- y
  f <- paste0("y", "~", paste0(names(.data), collapse = "+"))
  lm(f, data = .data, model.frame = FALSE, y = FALSE, X = FALSE)
}
