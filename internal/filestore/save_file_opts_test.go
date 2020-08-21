package filestore_test

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"gitlab.com/gitlab-org/gitlab-workhorse/internal/api"
	"gitlab.com/gitlab-org/gitlab-workhorse/internal/config"
	"gitlab.com/gitlab-org/gitlab-workhorse/internal/filestore"
	"gitlab.com/gitlab-org/gitlab-workhorse/internal/objectstore/test"
)

func TestSaveFileOptsLocalAndRemote(t *testing.T) {
	tests := []struct {
		name          string
		localTempPath string
		presignedPut  string
		partSize      int64
		isLocal       bool
		isRemote      bool
		isMultipart   bool
	}{
		{
			name:          "Only LocalTempPath",
			localTempPath: "/tmp",
			isLocal:       true,
		},
		{
			name:          "Both paths",
			localTempPath: "/tmp",
			presignedPut:  "http://example.com",
			isLocal:       true,
			isRemote:      true,
		},
		{
			name: "No paths",
		},
		{
			name:         "Only remoteUrl",
			presignedPut: "http://example.com",
			isRemote:     true,
		},
		{
			name:        "Multipart",
			partSize:    10,
			isRemote:    true,
			isMultipart: true,
		},
		{
			name:          "Multipart and Local",
			partSize:      10,
			localTempPath: "/tmp",
			isRemote:      true,
			isMultipart:   true,
			isLocal:       true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			opts := filestore.SaveFileOpts{
				LocalTempPath: test.localTempPath,
				PresignedPut:  test.presignedPut,
				PartSize:      test.partSize,
			}

			assert.Equal(t, test.isLocal, opts.IsLocal(), "IsLocal() mismatch")
			assert.Equal(t, test.isRemote, opts.IsRemote(), "IsRemote() mismatch")
			assert.Equal(t, test.isMultipart, opts.IsMultipart(), "IsMultipart() mismatch")
		})
	}
}

func TestGetOpts(t *testing.T) {
	tests := []struct {
		name             string
		multipart        *api.MultipartUploadParams
		customPutHeaders bool
		putHeaders       map[string]string
	}{
		{
			name: "Single upload",
		}, {
			name: "Multipart upload",
			multipart: &api.MultipartUploadParams{
				PartSize:    10,
				CompleteURL: "http://complete",
				AbortURL:    "http://abort",
				PartURLs:    []string{"http://part1", "http://part2"},
			},
		},
		{
			name:             "Single upload with custom content type",
			customPutHeaders: true,
			putHeaders:       map[string]string{"Content-Type": "image/jpeg"},
		}, {
			name: "Multipart upload with custom content type",
			multipart: &api.MultipartUploadParams{
				PartSize:    10,
				CompleteURL: "http://complete",
				AbortURL:    "http://abort",
				PartURLs:    []string{"http://part1", "http://part2"},
			},
			customPutHeaders: true,
			putHeaders:       map[string]string{"Content-Type": "image/jpeg"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			apiResponse := &api.Response{
				TempPath: "/tmp",
				RemoteObject: api.RemoteObject{
					Timeout:          10,
					ID:               "id",
					GetURL:           "http://get",
					StoreURL:         "http://store",
					DeleteURL:        "http://delete",
					MultipartUpload:  test.multipart,
					CustomPutHeaders: test.customPutHeaders,
					PutHeaders:       test.putHeaders,
				},
			}
			deadline := time.Now().Add(time.Duration(apiResponse.RemoteObject.Timeout) * time.Second)
			opts := filestore.GetOpts(apiResponse)

			assert.Equal(t, apiResponse.TempPath, opts.LocalTempPath)
			assert.WithinDuration(t, deadline, opts.Deadline, time.Second)
			assert.Equal(t, apiResponse.RemoteObject.ID, opts.RemoteID)
			assert.Equal(t, apiResponse.RemoteObject.GetURL, opts.RemoteURL)
			assert.Equal(t, apiResponse.RemoteObject.StoreURL, opts.PresignedPut)
			assert.Equal(t, apiResponse.RemoteObject.DeleteURL, opts.PresignedDelete)
			if test.customPutHeaders {
				assert.Equal(t, opts.PutHeaders, apiResponse.RemoteObject.PutHeaders)
			} else {
				assert.Equal(t, opts.PutHeaders, map[string]string{"Content-Type": "application/octet-stream"})
			}

			if test.multipart == nil {
				assert.False(t, opts.IsMultipart())
				assert.Empty(t, opts.PresignedCompleteMultipart)
				assert.Empty(t, opts.PresignedAbortMultipart)
				assert.Zero(t, opts.PartSize)
				assert.Empty(t, opts.PresignedParts)
			} else {
				assert.True(t, opts.IsMultipart())
				assert.Equal(t, test.multipart.CompleteURL, opts.PresignedCompleteMultipart)
				assert.Equal(t, test.multipart.AbortURL, opts.PresignedAbortMultipart)
				assert.Equal(t, test.multipart.PartSize, opts.PartSize)
				assert.Equal(t, test.multipart.PartURLs, opts.PresignedParts)
			}
		})
	}
}

func TestGetOptsDefaultTimeout(t *testing.T) {
	deadline := time.Now().Add(filestore.DefaultObjectStoreTimeout)
	opts := filestore.GetOpts(&api.Response{})

	assert.WithinDuration(t, deadline, opts.Deadline, time.Minute)
}

func TestUseWorkhorseClientEnabled(t *testing.T) {
	cfg := filestore.ObjectStorageConfig{
		Provider: "AWS",
		S3Config: config.S3Config{
			Bucket: "test-bucket",
			Region: "test-region",
		},
		S3Credentials: config.S3Credentials{
			AwsAccessKeyID:     "test-key",
			AwsSecretAccessKey: "test-secret",
		},
	}

	missingCfg := cfg
	missingCfg.S3Credentials = config.S3Credentials{}

	iamConfig := missingCfg
	iamConfig.S3Config.UseIamProfile = true

	tests := []struct {
		name                string
		UseWorkhorseClient  bool
		remoteTempObjectID  string
		objectStorageConfig filestore.ObjectStorageConfig
		expected            bool
	}{
		{
			name:                "all direct access settings used",
			UseWorkhorseClient:  true,
			remoteTempObjectID:  "test-object",
			objectStorageConfig: cfg,
			expected:            true,
		},
		{
			name:                "missing AWS credentials",
			UseWorkhorseClient:  true,
			remoteTempObjectID:  "test-object",
			objectStorageConfig: missingCfg,
			expected:            false,
		},
		{
			name:                "direct access disabled",
			UseWorkhorseClient:  false,
			remoteTempObjectID:  "test-object",
			objectStorageConfig: cfg,
			expected:            false,
		},
		{
			name:                "with IAM instance profile",
			UseWorkhorseClient:  true,
			remoteTempObjectID:  "test-object",
			objectStorageConfig: iamConfig,
			expected:            true,
		},
		{
			name:                "missing remote temp object ID",
			UseWorkhorseClient:  true,
			remoteTempObjectID:  "",
			objectStorageConfig: cfg,
			expected:            false,
		},
		{
			name:               "missing S3 config",
			UseWorkhorseClient: true,
			remoteTempObjectID: "test-object",
			expected:           false,
		},
		{
			name:               "missing S3 bucket",
			UseWorkhorseClient: true,
			remoteTempObjectID: "test-object",
			objectStorageConfig: filestore.ObjectStorageConfig{
				Provider: "AWS",
				S3Config: config.S3Config{},
			},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			apiResponse := &api.Response{
				TempPath: "/tmp",
				RemoteObject: api.RemoteObject{
					Timeout:            10,
					ID:                 "id",
					UseWorkhorseClient: test.UseWorkhorseClient,
					RemoteTempObjectID: test.remoteTempObjectID,
				},
			}
			deadline := time.Now().Add(time.Duration(apiResponse.RemoteObject.Timeout) * time.Second)
			opts := filestore.GetOpts(apiResponse)
			opts.ObjectStorageConfig = test.objectStorageConfig

			require.Equal(t, apiResponse.TempPath, opts.LocalTempPath)
			require.WithinDuration(t, deadline, opts.Deadline, time.Second)
			require.Equal(t, apiResponse.RemoteObject.ID, opts.RemoteID)
			require.Equal(t, apiResponse.RemoteObject.UseWorkhorseClient, opts.UseWorkhorseClient)
			require.Equal(t, test.expected, opts.UseWorkhorseClientEnabled())
			require.Equal(t, test.UseWorkhorseClient, opts.IsRemote())
		})
	}
}

func TestGoCloudConfig(t *testing.T) {
	mux, _, cleanup := test.SetupGoCloudFileBucket(t, "azblob")
	defer cleanup()

	tests := []struct {
		name     string
		provider string
		url      string
		valid    bool
	}{
		{
			name:     "valid AzureRM config",
			provider: "AzureRM",
			url:      "azblob:://test-container",
			valid:    true,
		},
		{
			name:     "invalid GoCloud scheme",
			provider: "AzureRM",
			url:      "unknown:://test-container",
			valid:    true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			apiResponse := &api.Response{
				TempPath: "/tmp",
				RemoteObject: api.RemoteObject{
					Timeout:            10,
					ID:                 "id",
					UseWorkhorseClient: true,
					RemoteTempObjectID: "test-object",
					ObjectStorage: &api.ObjectStorageParams{
						Provider: test.provider,
						GoCloudConfig: config.GoCloudConfig{
							URL: test.url,
						},
					},
				},
			}
			deadline := time.Now().Add(time.Duration(apiResponse.RemoteObject.Timeout) * time.Second)
			opts := filestore.GetOpts(apiResponse)
			opts.ObjectStorageConfig.URLMux = mux

			require.Equal(t, apiResponse.TempPath, opts.LocalTempPath)
			require.Equal(t, apiResponse.RemoteObject.RemoteTempObjectID, opts.RemoteTempObjectID)
			require.WithinDuration(t, deadline, opts.Deadline, time.Second)
			require.Equal(t, apiResponse.RemoteObject.ID, opts.RemoteID)
			require.Equal(t, apiResponse.RemoteObject.UseWorkhorseClient, opts.UseWorkhorseClient)
			require.Equal(t, test.provider, opts.ObjectStorageConfig.Provider)
			require.Equal(t, apiResponse.RemoteObject.ObjectStorage.GoCloudConfig, opts.ObjectStorageConfig.GoCloudConfig)
			require.True(t, opts.UseWorkhorseClientEnabled())
			require.Equal(t, test.valid, opts.ObjectStorageConfig.IsValid())
			require.True(t, opts.IsRemote())
		})
	}
}
