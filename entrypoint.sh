#!/bin/bash
set -e

clickhouse client --user=${CH_USERNAME} --password=${CH_PASSWORD} -n <<-EOSQL

    CREATE DATABASE vr;

    CREATE TABLE vr.video (
        uuid UUID DEFAULT generateUUIDv4(),
        url String,
        is_processed Bool,
        dttm DateTime DEFAULT now()
    )
    ENGINE = MergeTree()
    PARTITION BY is_processed
    PRIMARY KEY uuid;

    CREATE TABLE vr.video_stat (
        amount Int32,
        processed Int32
    )
    ENGINE = AggregatingMergeTree
    ORDER BY (amount, processed);

    CREATE TABLE vr.req_stat (
        start_time DateTime,
        end_time Nullable(DateTime),
        text String,
        req_from IPv4
    )
    ENGINE = Log;

    CREATE MATERIALIZED VIEW IF NOT EXISTS vr.video_stat_mv
    TO vr.video_stat
    AS SELECT
           count(uuid) AS amount,
           sum(is_processed) AS processed
    FROM vr.video;

    CREATE TABLE vr.embeddings (
        uuid UUID,
        image_model String,
        image_embedding Array(Float32),
        dttm DateTime DEFAULT now()
    )
    ENGINE = MergeTree
    PARTITION BY image_model
    ORDER BY uuid;

    CREATE TABLE vr.audio_embeddings (
        uuid UUID,
        text_model String,
        text Nullable(String),
        text_embedding Array(Float32) DEFAULT [1, 1, 1, 1],
        dttm DateTime DEFAULT now()
    )
    ENGINE = MergeTree
    PARTITION BY text_model
    ORDER BY uuid;

    CREATE TABLE vr.face_embeddings (
        uuid UUID,
        image_model String,
        image_embedding Array(Float32),
        dttm DateTime DEFAULT now()
    )
    ENGINE = MergeTree
    PARTITION BY image_model
    ORDER BY uuid;

    SET allow_experimental_annoy_index = 1;

    create table vr.embeddings_annoy (
        uuid UUID,
        image_model String,
        image_embedding Array(Float32),
        INDEX annoy_image image_embedding TYPE annoy('cosineDistance', 100) GRANULARITY 100000,
    )
    ENGINE = MergeTree
    ORDER BY uuid;

    create table vr.embeddings_mean (
      uuid UUID,
      image_embedding Array(Float32)
    )
    ENGINE = MergeTree
    ORDER BY uuid;

    create table vr.embeddings_max (
      uuid UUID,
      image_embedding Array(Float32)
    )
    ENGINE = MergeTree
    ORDER BY uuid;

    truncate table vr.embeddings_mean;
    truncate table vr.embeddings_max;

    insert into vr.embeddings_mean
    select uuid, sumForEach(image_embedding) / count(image_embedding) as image_embedding from vr.embeddings
    group by uuid;

    insert into vr.embeddings_max
    select uuid, maxForEach(image_embedding) as image_embedding from vr.embeddings
    group by uuid;


    CREATE TABLE vr.coef (
        alpha Float32,
        beta Float32,
        strategy String,
        score Nullable(Float32)
    )
    ENGINE = Log;

    CREATE ROLE analytics;
    GRANT SELECT ON vr.* TO analytics;
    CREATE USER monitor IDENTIFIED WITH sha256_password BY 'monitor3000';
    GRANT analytics TO monitor;

EOSQL
