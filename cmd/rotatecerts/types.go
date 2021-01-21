package rotatecerts

import (
	"context"
	"time"

	"github.com/Azure/aks-engine/pkg/armhelpers"
	"github.com/pkg/errors"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/util/retry"
)

type ARMClient struct {
	client    armhelpers.AKSEngineClient
	timeout   time.Duration
	backoff   wait.Backoff
	retryFunc func(err error) bool
}

// NewARMClient ...
func NewARMClient(client armhelpers.AKSEngineClient, interval, timeout time.Duration) *ARMClient {
	return &ARMClient{
		client:  client,
		timeout: timeout,
		backoff: wait.Backoff{
			Steps:    int(int64(timeout/time.Millisecond) / int64(interval/time.Millisecond)),
			Duration: interval,
			Factor:   1.0,
			Jitter:   0.0,
		},
		retryFunc: func(err error) bool { return err != nil },
	}
}

// GetVirtualMachinePowerState ...
func (arm *ARMClient) GetVirtualMachinePowerState(resourceGroup, vmName string) (string, error) {
	var err error
	status := ""
	err = retry.OnError(arm.backoff, arm.retryFunc, func() error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		status, err = arm.client.GetVirtualMachinePowerState(ctx, resourceGroup, vmName)
		if err != nil {
			return errors.Errorf("fetching virtual machine resource")
		}
		return nil
	})
	return status, err
}

// RestartVirtualMachine ...
func (arm *ARMClient) RestartVirtualMachine(resourceGroup, vmName string) error {
	var err error
	err = retry.OnError(arm.backoff, arm.retryFunc, func() error {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		defer cancel()
		if err = arm.client.RestartVirtualMachine(ctx, resourceGroup, vmName); err != nil {
			return errors.Errorf("restarting virtual machine")
		}
		return nil
	})
	return err
}
