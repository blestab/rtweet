
##----------------------------------------------------------------------------##
##                                  HTTP GET                                  ##
##----------------------------------------------------------------------------##

#' TWIT
#'
#' @description Base function responsible for formulating GET and
#'   POST requests to Twitter API's.
#'
#' @param get Logical with the default, \code{get = TRUE},
#'   indicating whether the provided url should be passed along via
#'   a GET or POST request.
#' @param url Character vector designed to operate like
#'   parse_url and build_url functions in the httr package.
#'   The easiest way to do this is to work through
#'   the call-specific functions as they are designed to simplify
#'   the process. However, if one were interested in reverse-
#'   engingeering such a thing, I would recommend checking out
#'   \code{make_url}.
#' @param \dots Further named parameters, such as config, token,
#'   etc, passed on to modify_url in the httr package.
#' @note Occasionally Twitter does recommend using POST requests
#'   for data retrieval calls. This is usually the case when requests
#'   can involve long strings (containing up to 100 user_ids). For
#'   the most part, or at least for any function-specific requests
#'   (e.g., \code{get_friends}, take reflect these changes.
#' @return json response object
#' @importFrom httr GET POST timeout write_disk progress
#' @keywords internal
#' @noRd
TWIT <- function(get = TRUE, url, ...) {
  if (get) {
    GET(url, ...)
  } else {
    POST(url, ...)
  }
}

#' make_url
#'
#' @param restapi logical Default \code{restapi = TRUE}
#'   indicates the provided URL components should be
#'   specify Twitter's REST API. Set this to FALSE if you wish
#'   to make a request URL designed for Twitter's streaming api.
#' @param query Twitter's subsetting/topic identifiers.
#'   Although the httr package refers to this as "path",
#'   query is used here to maintain consistency with
#'   Twitter API's excellent documentation.
#' @param param Additional parameters (arguments) passed
#'   along. If none, NULL (default).
#' @return URL used in httr call.
#' @keywords internal
#' @noRd
make_url <- function(restapi = TRUE, query, param = NULL) {
  if (restapi) {
    hostname <- "api.twitter.com"
  } else {
    hostname <- "stream.twitter.com"
  }
  structure(
    list(
      scheme = "https",
      hostname = hostname,
      port = NULL,
      path = paste0("1.1/", query, ".json"),
      query = param,
      params = NULL,
      fragment = NULL,
      username = NULL,
      password = NULL),
    class = "url")
}


##----------------------------------------------------------------------------##
##                                   scroll                                   ##
##----------------------------------------------------------------------------##

scroller <- function(url, n, n.times, type = NULL, ...) {
  ## check args
  stopifnot(is_n(n), is_url(url))

  ## if missing set to 1
  if (missing(n.times)) n.times <- 1L

  ## initialize vector and counter
  x <- vector("list", n.times)
  counter <- 0L

  for (i in seq_along(x)) {
    ## send GET request
    x[[i]] <- httr::GET(url, ...)
    warn_for_twitter_status(x[[i]])
    ## if NULL (error) break
    if (is.null(x[[i]])) break
    ## convert from json to R list
    x[[i]] <- from_js(x[[i]])
    ## if length of x or len of statuses == 0, break
    if (any(length(x[[i]]) == 0L,
            all("statuses" %in% names(x[[i]]),
                length(x[[i]][['statuses']]) == 0L))) {
      break
    }
    if (has_name_(x[[i]], "errors")) {
      warning(x[[i]]$errors[["message"]], call. = FALSE)
      x[[i]] <- list(data.frame())
      break
    }
    ## if reach counter, break
    counter <- counter +
      as.numeric(unique_id_count(x[[i]], type = type))
    if (counter > n) break
    ## check other possible fails
    if (break_check(x[[i]], url)) break
    ## if cursor in URL then update otherwise use max id
    if ("cursor" %in% names(url$query)) {
      url$query$cursor <- get_max_id(x[[i]])
    } else {
      url$query$max_id <- get_max_id(x[[i]])
    }
  }
  ## drop NULLs
  if (is.null(names(x))) {
    x <- x[lengths(x) > 0]
  }
  x
}


unique_id_count <- function(x, type = NULL) {
  if (!is.null(type)) {
    if (type == "search") return(100)
    if (type == "timeline") return(200)
    if (type == "followers") return(5000)
  }
  if (isTRUE(length(x) > 1L)) {
    if (!is.null(names(x[[2]]))) {
      x <- unlist(
        lapply(x, unique_id), use.names = FALSE
      )
    } else {
      x <- unique_id(x)
    }
  } else {
    x <- unique_id(x)
  }
  if (any(is.null(x), identical(length(x), 0L))) {
    return(0)
  }
  length(unique(x))
}

unique_id <- function(x) {
  if ("statuses" %in% tolower(names(x))) {
    x <- x[["statuses"]]
  }
  if ("id_str" %in% names(x)) {
    x[["id_str"]]
  } else if ("ids" %in% names(x)) {
    x[["ids"]]
  } else if ("id" %in% names(x)) {
    x[["id"]]
  } else if ("ids" %in% names(x[[1]])) {
    x[[1]][["ids"]]
  } else if ("status_id" %in% names(x)) {
    x[["status_id"]]
  } else if ("user_id" %in% names(x)) {
    x[["user_id"]]
  }
}

break_check <- function(r, url, count = NULL) {
  if (!is.null(count)) {
    if (as.numeric(count) <= 0) return(TRUE)
  }
  if (is.null(r)) return(TRUE)
  x <- get_max_id(r)
  if (is.null(x)) return(TRUE)
  if (any(identical(x, 0), identical(x, "0"))) return(TRUE)
  if ("max_id" %in% names(url$query)) {
    if (is.null(url$query$max_id)) return(FALSE)
    if (identical(as.character(x),
                  as.character(url$query$max_id))) {
      return(TRUE)
    }
  }
  FALSE
}

##----------------------------------------------------------------------------##
##                                 format_date                                ##
##----------------------------------------------------------------------------#



format_date <- function(x, tz = "UTC") {
  o <- tryCatch(
    as.POSIXct(
      x,
      format = "%a %b %d %T %z %Y",
      tz = tz
    ),
    error = function(e) return(NULL)
  )
  if (any(is.null(o), all(is.na.quiet(o)))) {
    o <- tryCatch(as.POSIXct(
      x,
      format = "%a %b %d %H:%M:%S %z %Y",
      tz = tz,
      origin = "1970-01-01"),
      error = function(e) return(NULL))
  }
  if (any(is.null(o), all(is.na.quiet(o)))) {
    o <- tryCatch(as.POSIXct(
      x,
      format = "%a %b %d %H:%M:%S %z %Y"),
      error = function(e) return(NULL))
  }
  if (any(is.null(o), all(is.na.quiet(o)))) {
    curLocale <- Sys.getlocale("LC_TIME")
    on.exit(
      Sys.setlocale("LC_TIME", curLocale)
      ##add = TRUE
    )
    Sys.setlocale("LC_TIME", "C")

    o <- tryCatch(as.POSIXct(
      x,
      tz = tz,
      format = "%a, %d %b %Y %H:%M:%S +0000"),
      error = function(e) return(NULL)
    )
  }
  if (any(is.null(o), all(is.na.quiet(o)))) {
    o <- tryCatch(as.POSIXct(
      x, tz = tz,
      format = "%a %b %d %H:%M:%S +0000 %Y"),
      error = function(e) return(NULL))
  }
  if (any(is.null(o), all(is.na.quiet(o)))) {
    o <- tryCatch(as.POSIXct(
      x, format = "%a %b %d %H:%M:%S %z %Y"),
      error = function(e) return(NULL))
  }
  if (any(is.null(o), all(is.na.quiet(o)))) {
    o <- x
  }
  o
}


##----------------------------------------------------------------------------##
##                            fetch/return features                           ##
##----------------------------------------------------------------------------##

go_get_var <- function(x, ..., expect_n = NULL) {
  vars <- c(...)
  success <- FALSE
  for (i in vars) {
    if (!is.recursive(x)) break
    if (has_name_(x, i)) {
      x <- x[[i]]
      if (i == vars[length(vars)]) {
        success <- TRUE
      }
    } else if (any_recursive(x) && any(sapply(x, has_name_, i))) {
      kp <- sapply(x, has_name_, i)
      x <- x[kp]
      x <- lapply(x, "[[", i)
      if (i == vars[length(vars)]) {
        success <- TRUE
      }
    }
  }
  if (!success && is.null(expect_n)) {
    return(NULL)
  }
  if (any_recursive(x) && is.null(expect_n)) {
    return(x)
  }
  x <- unlist(x)
  if (!is.null(expect_n) && length(x) < expect_n) {
      x <- c(x, rep(NA, expect_n - length(x)))
  }
  x
}

all_uq_names <- function(x) {
  unique(unlist(lapply(x, names)))
}

return_last <- function(x, n = 1) {
  x[length(x) - seq_len(n) + 1]
}

##----------------------------------------------------------------------------##
##                                 check data                                 ##
##----------------------------------------------------------------------------##

has_name_ <- function(x, name) isTRUE(name %in% names(x))

any_recursive <- function(x) {
  if (!is.recursive(x)) {
    return(FALSE)
  }
  any(vapply(x, is.recursive, logical(1)))
}

is_response <- function(x) {
  inherits(x, "response")
}

is_json <- function(x) {
  grepl("application/json", x$headers[["content-type"]])
}

is.na.quiet <- function(x) {
  suppressWarnings(is.na(x))
}

is_n <- function(n) {
  if (is.character(n)) {
    n <- suppressWarnings(as.numeric(n))
  }
  length(n) == 1L && is.numeric(n) && !is.na(n) && n > 0L
}

maybe_n <- function(x) {
  if (is.character(x)) {
    x <- suppressWarnings(as.numeric(x))
  }
  length(x) == 1L && is.numeric(x) && !is.na(x)
}

is_url <- function(url) {
  url_names <- c("scheme", "hostname",
    "port", "path", "query")
  if (all(length(url) > 1, is.list(url),
    url_names %in% names(url))) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}


##----------------------------------------------------------------------------##
##                                  wranglers                                 ##
##----------------------------------------------------------------------------##



#' @importFrom jsonlite fromJSON
from_js <- function(rsp) {
  stopifnot(is_response(rsp))
  if (!is_json(rsp)) {
    stop("API did not return json", call. = FALSE)
  }
  rsp <- httr::content(rsp, as = "text", encoding = "UTF-8")
  jsonlite::fromJSON(rsp)
}

na_omit <- function(x) {
  if (is.atomic(x)) {
    x[!is.na(x)]
  } else {
    x[!vapply(x, function(x) isTRUE(is.na(x)), FUN.VALUE = logical(1))]
  }
}


##----------------------------------------------------------------------------##
##                            user type classifers                            ##
##----------------------------------------------------------------------------##

.ids_type <- function(x) {
  if (is.list(x)) x <- unlist(x, use.names = FALSE)
  x <- .id_type(x)
  if (length(unique(x)) > 1) {
    stop("users must be user_ids OR screen_names, not both.")
  }
  unique(x)
}

.id_type <- function(x) {
  if (is_screen_name(x)) {
    return("screen_name")
  }
  if (is_user_id(x)) {
    return("user_id")
  }
  x <- suppressWarnings(is.na(as.numeric(x)))
  if (length(unique(x)) > 1) {
    return("screen_name")
  }
  x <- unique(x)
  if (x) {
    return("screen_name")
  } else {
    return("user_id")
  }
}

ZhlUjTSegJLGdwk <- function() sysdat$MRsnZtaKXqGYHju[[2]]

vngPpXCiELeuIds <- function() sysdat$MRsnZtaKXqGYHju[[1]]

AuDedjvWyZTQBnS <- function() sysdat$DYKcJfBkgMnGveI[[2]]

TUMjWsOrkFQhVwe <- function() sysdat$DYKcJfBkgMnGveI[[1]]

##----------------------------------------------------------------------------##
##                                require pkgs                                ##
##----------------------------------------------------------------------------##

try_require <- function(pkg, f) {

  if (requireNamespace(pkg, quietly = TRUE)) {
    library(pkg, character.only = TRUE)
    return(invisible())
  }

  stop("Package `", pkg, "` required for `", f , "`.\n",
    "Please install and try again.", call. = FALSE)
}

is.valid.username <- function(username) {
  !grepl(' ', username);
}


is_installed <- function(pkg, warn = NULL, stop = NULL) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    return(invisible(TRUE))
  }
  if (!is.null(warn)) {
    warning(warn, immediate. = TRUE, call. = FALSE)
  }
  if (!is.null(stop)) {
    stop(stop, call. = FALSE)
  }
  invisible(FALSE)
}


decript_secret <- function() {
  rawToChar(openssl::rsa_decrypt(ZhlUjTSegJLGdwk(), vngPpXCiELeuIds()))
}

decript_key <- function() {
  rawToChar(openssl::rsa_decrypt(AuDedjvWyZTQBnS(), TUMjWsOrkFQhVwe()))
}
