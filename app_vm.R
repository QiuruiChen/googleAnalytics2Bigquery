setwd('.')

# if install packages in ubutun: https://stackoverflow.com/questions/20923209/problems-installing-the-devtools-package
# if you set up vm, about transfering files into vm: https://cloud.google.com/compute/docs/instances/transfer-files
if(!require(googleAnalyticsR)) install.packages("googleAnalyticsR", dependencies = TRUE)
library(googleAnalyticsR)
if(!require(googleCloudStorageR)) install.packages("googleCloudStorageR", dependencies = TRUE)
library(googleCloudStorageR)

if(!require(bigrquery)) install.packages("bigrquery", dependencies = TRUE)
library(bigrquery)

## non-interactive login in google analytics
options(
  gargle_oauth_cache = ".secrets",
  gargle_oauth_email = "your email",
  gargle_quiet = FALSE
)
googleAuthR::gar_set_client(json ="your_client_secrets.json",
                            scopes =c("https://www.googleapis.com/auth/analytics",
                                      "https://www.googleapis.com/auth/devstorage.full_control",
                                      "https://www.googleapis.com/auth/analytics.edit"),
                            activate="offline")

ga_auth(email="rachel@intellicare.nl")

## non-interactive login bigquery
bq_auth(
  email = "your email",
  path='your_project_service_account.json',
  scopes = c("https://www.googleapis.com/auth/bigquery",
             "https://www.googleapis.com/auth/cloud-platform"),
  use_oob = gargle::gargle_oob_default()
)

# extract data
account_list <- ga_account_list()
viewId <- account_list$viewId[2]

meta <- ga_meta()
head(meta)

## pick the account_list$viewId you want to see data for.
## metrics and dimensions can have or have not "ga:" prefix

not_localhost <- dim_filter("hostname","BEGINS_WITH","localhost",not = TRUE)
rec_content <- dim_filter("pagePath","BEGINS_WITH","/content",not = FALSE)
dim_fc <- filter_clause_ga4(list(not_localhost, rec_content), operator = "AND")

som <- function(x) {
  as.Date(format(x, "%Y-%m-01"))
}
eom <- function(x) {
  som(som(x) + 35) - 1
}
starDate <- som(som(Sys.Date()) - 1)
endDate <-  som(Sys.Date()) - 1

# extract data from previous month
gadata <- google_analytics(viewId,
                           date_range= c(starDate,endDate),
                           metrics = c('timeOnPage'),
                           dimensions = c('ga:clientId','pagePath','hostname'),
                           dim_filters = dim_fc,
                           max=-1)

cids <- google_analytics(viewId, date_range = c(starDate,endDate),
                         metrics = "sessions", dimensions = "clientId")
users <- ga_clientid_activity(cids$clientId,
                              viewId = viewId,
                              date_range = c(starDate,endDate))


users$hits$customDimension <- vapply(users$hits$customDimension, paste, collapse = ", ", character(1L))
users$hits$ecommerce <- vapply(users$hits$ecommerce, paste, collapse = ", ", character(1L))
users$hits$goals <- vapply(users$hits$goals, paste, collapse = ", ", character(1L))


## ==========
# save dataframe into csv files into google cloud storage
## ===========
# currentTime <- Sys.Date()
# upload_try <- gcs_upload(cids,bucket="rec_edcare_ga", name = paste(currentTime, "clientIds.csv", sep=""))
# upload_try <- gcs_upload(users$sessions,bucket="rec_edcare_ga",
#                          name = paste(currentTime, "users_sessions.csv", sep=""))
# upload_try <- gcs_upload(users$hits,bucket="rec_edcare_ga",
#                          name = paste(currentTime,"users_hits.csv", sep=""))
# upload_try <- gcs_upload(gadata,bucket="rec_edcare_ga",
#                          name = paste(currentTime, "rec_data.csv", sep=""))


## ===========================
# save rec data into bigquery
## ===========================
# set my project ID and dataset name
project_id <- "buddie-270710"
dataset_name <- "ga_data"


## upload recomender raw data into bigquery
gadata$extractedDate <- Sys.Date()
# sapply(gadata, class)
players_table = bq_table(project = project_id, dataset = dataset_name, table = 'rec_data')
if (! bq_table_exists(x=players_table)){
  bq_table_create(x = players_table, fields = as_bq_fields(gadata))
}
bq_table_upload(x=players_table, values= gadata,
                create_disposition='CREATE_IF_NEEDED',
                write_disposition='WRITE_APPEND')

## user sessions
users$sessions$extractedDate <- Sys.Date()
sapply(users$sessions, class)

players_table = bq_table(project = project_id, dataset = dataset_name, table = 'users_sessions')
if (!bq_table_exists(x=players_table)){
  bq_table_create(x = players_table, fields = as_bq_fields(users$sessions))
}
bq_table_upload(x=players_table, values= users$sessions,
                create_disposition='CREATE_IF_NEEDED',
                write_disposition='WRITE_APPEND')

## user hits
users$hits$extractedDate <- Sys.Date()
sapply(users$hits, class)
players_table = bq_table(project = project_id, dataset = dataset_name, table = 'users_hits')
if (! bq_table_exists(x=players_table)){
  bq_table_create(x = players_table, fields = as_bq_fields(users$hits))
}
bq_table_upload(x=players_table, values= users$hits,
                create_disposition='CREATE_IF_NEEDED',
                write_disposition='WRITE_APPEND')
