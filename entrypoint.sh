#!/bin/bash
set -e

clickhouse client -n <<-EOSQL

    CREATE DATABASE vr;

    CREATE TABLE vr.video (
        uuid UUID DEFAULT generateUUIDv4(),
        url String,
        is_processed Bool
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
        num Int64,
        image_model String,
        image_embedding Array(Float32),
        image_metric Nullable(Float32)
    )
    ENGINE = MergeTree
    PARTITION BY image_model
    ORDER BY (uuid, num);

    CREATE TABLE vr.audio_embeddings (
        uuid UUID,
        num Int64,
        text_model String,
        text Nullable(String),
        text_embedding Array(Float32) DEFAULT [1, 1, 1, 1]
    )
    ENGINE = MergeTree
    PARTITION BY text_model
    ORDER BY (uuid, num);

    SET allow_experimental_annoy_index = 1;

    create table vr.embeddings_annoy (
        uuid UUID,
        num Int64,
        image_model String,
        image_embedding Array(Float32),
        INDEX annoy_image image_embedding TYPE annoy('cosineDistance', 1000) GRANULARITY 1000,
    )
    ENGINE = MergeTree
    partition by image_model
    ORDER BY (uuid, num);

    CREATE TABLE vr.coef (
        alpha Float32,
        beta Float32,
        score Nullable(Float32)
    )
    ENGINE = Log;

    CREATE ROLE analytics;
    GRANT SELECT ON vr.* TO analytics;
    CREATE USER monitor IDENTIFIED WITH sha256_password BY 'monitor3000';
    GRANT analytics TO monitor;

EOSQL
