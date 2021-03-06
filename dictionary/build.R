setwd(here::here())
source('dictionary/utilities.R')

# Source: TRUE -- web source has priority. FALSE -- backup source has priority. 
src = c('cldr' = FALSE,
        'cow_cs' = FALSE,
        'ecb' = FALSE,
        'eurostat' = FALSE,
        'fao' = FALSE,
        'fips' = FALSE,
        'genc' = FALSE,
        'gw' = FALSE,
        'ioc' = FALSE,
        'icao' = FALSE,
        'iso' = FALSE,
        'polity4_cs' = FALSE,
        'un' = FALSE,
        'un_names' = FALSE,
#        'unpd' = FALSE, # dead url in get_unpd.R data moved to data_static.csv
        'vdem_cs' = FALSE,
        'world_bank' = FALSE,
        'world_bank_api' = FALSE,
        'world_bank_region' = FALSE,
        'wvs' = FALSE)
src = c('static' = TRUE, src) # static must always be true

# Flip toggle back to TRUE if dataset is not available in backup
bak = readRDS('data/backup.rds')
src[!names(src) %in% names(bak)] = TRUE

# Download
dat = lapply(names(src)[src], LoadSource)
names(dat) = names(src)[src]

# Sanity checks (drop datasets that fail)
dat = SanityCheck(dat)

# Overwrite from backup if src toggle is FALSE and dataset is already stored in backup file
for (n in names(src)[!src]) {
    if (n %in% names(bak)) {
        cat('Loading', n, 'from backup.\n')
        dat[[n]] = bak[[n]]
    }
}

# Sanity check: duplicate merge id
for (n in names(dat)) {
    if ('year' %in% colnames(dat[[n]])) {
        idx = paste(dat[[n]]$country.name.en.regex, dat[[n]]$year)
    } else {
        idx = dat[[n]]$country.name.en.regex
    }
    if (any(duplicated(idx))) {
        stop('Dataset ', n, ' includes duplicate country (or country-year) indices.')
    }
}

# Cross-section
cs = purrr::reduce(dat, dplyr::left_join, by = 'country.name.en.regex')

# English names with priority ordering
priority = c('cldr.name.en', 'iso.name.en', 'un.name.en', 'cow.name', 'p4.name', 'vdem.name', 'country.name.en')
cs$country.name = NA
for (i in priority) {
    cs$country.name = ifelse(is.na(cs$country.name), cs[, i], cs$country.name)
}
cs$country.name.en = cs$country.name
cs$country.name = NULL

# Panel
tmp = cs %>% dplyr::select(-dplyr::matches('cldr|p4|cow|vdem'))
panel = read.csv('dictionary/data_panel.csv', na.strings = '') %>%
        dplyr::left_join(tmp, by = 'country.name.en.regex')

# Clean-up
sort_col = function(x) { # cldr columns at the end
    x = x[, sort(colnames(x))]
    idx = grepl('^cldr', colnames(x))
    x = cbind(x[, !idx], x[, idx])
    return(x)
}
cs = sort_col(cs)
panel = panel %>% select(country.name.en, year, order(names(.)))

# Sanity check: duplicates
idx = paste(panel$country.name.en, panel$year)
if (anyDuplicated(idx)) {
    stop('Duplicate country year observations in panel dataset')
}
if (anyDuplicated(cs$country.name.en)) {
    stop('Duplicate country observations in cross-sectional dataset')
}

# Encoding: convert to UTF-8 if there are non-ASCII characters
for (col in colnames(cs)[sapply(cs, class) == 'character']) {
    if (!all(na.omit(stringi::stri_enc_mark(cs[[col]])) == 'ASCII')) {
        cs[[col]] <- enc2utf8(cs[[col]])
    }
}
for (col in colnames(panel)[sapply(panel, class) == 'character']) {
    if (!all(na.omit(stringi::stri_enc_mark(panel[[col]])) == 'ASCII')) {
        panel[[col]] <- enc2utf8(panel[[col]])
    }
}

# Save files
codelist = cs
codelist_panel = panel
saveRDS(dat, 'data/backup.rds', compress = 'xz', version = 2)
save(codelist, file = 'data/codelist.rda', compress = 'xz', version = 2)
save(codelist_panel, file = 'data/codelist_panel.rda', compress = 'xz', version = 2)
