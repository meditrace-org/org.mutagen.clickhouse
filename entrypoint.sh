#!/bin/bash
set -e

clickhouse client -n <<-EOSQL

    CREATE DATABASE vr;

    create table vr.video (
        uuid UUID Default generateUUIDv4(),
        url String,
        is_processed Bool
    )
    ENGINE = MergeTree()
    partition by is_processed
    primary key uuid;

    create table vr.video_stat (
      amount Int32,
      processed Int32
     )
    ENGINE = AggregatingMergeTree
    ORDER BY (amount, processed);

    CREATE TABLE vr.req_stat (
        start_time DateTime,
        end_time Nullable(DateTime),
        text String,
        req_from IPv4,
    )
    ENGINE = Log;

    CREATE MATERIALIZED VIEW IF NOT EXISTS vr.video_stat_mv
    TO vr.video_stat
    as select
           count(uuid) as amount,
           sum(is_processed) as processed
    from  vr.video;

    create table vr.embeddings (
        uuid UUID,
        image_model String,
        image_embedding Array(Float32)
    )
    ENGINE = MergeTree
    partition by image_model
    ORDER BY uuid;

    create table vr.audio_embeddings (
        uuid UUID,
        text_model String,
        text Nullable(String),
        text_embedding Array(Float32) DEFAULT [1, 1, 1, 1],
    )
    ENGINE = MergeTree
    partition by text_model
    ORDER BY uuid;

    create table vr.face_embeddings (
        image_model String,
        image_embedding Array(Float32)
    )
    ENGINE = MergeTree
    partition by text_model
    ORDER BY uuid;

    SET allow_experimental_annoy_index = 1;

    create table vr.embeddings_annoy (
        uuid UUID,
        image_model String,
        `image_embedding` Array(Float32),
        INDEX annoy_image image_embedding TYPE annoy('cosineDistance', 1000) GRANULARITY 1000
    )
    ENGINE = MergeTree
    ORDER BY uuid;

    create table vr.coef (
        alfa Float32,
        beta Float32,
        gamma Float32,
        threshold Float32
    )
    ENGINE = Log;

    insert into vr.coef values (0.5, 0.5, 0.5);

    CREATE ROLE analytics;
    GRANT SELECT ON vr.* TO analytics;
    CREATE USER monitor IDENTIFIED WITH sha256_password BY 'monitor3000';
    GRANT analytics TO monitor;

EOSQL