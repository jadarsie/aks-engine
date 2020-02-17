// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT license.

package cmd

import (
	"context"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/Azure/aks-engine/pkg/api"
	"github.com/Azure/aks-engine/pkg/armhelpers"
	"github.com/Azure/aks-engine/pkg/engine"
	"github.com/Azure/aks-engine/pkg/helpers"
	"github.com/Azure/aks-engine/pkg/i18n"
	"github.com/leonelquinteros/gotext"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"golang.org/x/crypto/ssh"
	v1 "k8s.io/api/core/v1"
)

const (
	// TODO review descriptions
	getLogsName             = "get-logs"
	getLogsShortDescription = "get-logs"
	getLogsLongDescription  = "get-logs"
)

type getLogsCmd struct {
	authProvider

	// input
	resourceGroupName string
	sshPrivateKeyPath string
	apiserver         string
	location          string
	apiModelPath      string
	outputDirectory   string

	// locals
	containerService   *api.ContainerService
	apiVersion         string
	locale             *gotext.Locale
	client             armhelpers.AKSEngineClient
	masterNodes        []v1.Node
	linuxNodes         []v1.Node
	windowsNodes       []v1.Node
	sshConfig          *ssh.ClientConfig
	sshCommandExecuter func(command, apiserver, hostname string, config *ssh.ClientConfig) (string, error)
}

func newRetrieveLogsCmd() *cobra.Command {
	glc := getLogsCmd{
		authProvider:       &authArgs{},
		sshCommandExecuter: executeRemoteCmd,
	}

	command := &cobra.Command{
		Use:   getLogsName,
		Short: getLogsShortDescription,
		Long:  getLogsLongDescription,
		RunE: func(cmd *cobra.Command, args []string) error {
			if err := glc.validateArgs(cmd, args); err != nil {
				return errors.Wrap(err, "validating get-logs args")
			}
			if err := glc.loadAPIModel(); err != nil {
				return errors.Wrap(err, "loading API model")
			}
			return glc.run(cmd, args)
		},
	}

	// TODO review descriptions
	command.Flags().StringVarP(&glc.location, "location", "l", "", "location the cluster is deployed in (required)")
	command.MarkFlagRequired("location")
	command.Flags().StringVarP(&glc.resourceGroupName, "resource-group", "g", "", "the resource group where the cluster is deployed (required)")
	command.MarkFlagRequired("resource-group")
	command.Flags().StringVarP(&glc.apiModelPath, "api-model", "m", "", "path to the generated apimodel.json file (required)")
	command.MarkFlagRequired("api-model")
	command.Flags().StringVar(&glc.sshPrivateKeyPath, "ssh-private-key", "", "the filepath of a valid private ssh key to access the cluster's nodes (required)")
	command.MarkFlagRequired("ssh-private-key")
	command.Flags().StringVar(&glc.apiserver, "apiserver", "", "apiserver endpoint (required)")
	command.MarkFlagRequired("apiserver")
	command.Flags().StringVarP(&glc.outputDirectory, "output-directory", "o", "", "output directory where generated TLS artifacts will be saved (derived from DNS prefix if absent)")

	addAuthFlags(glc.getAuthArgs(), command.Flags())

	return command
}

func (glc *getLogsCmd) validateArgs(cmd *cobra.Command, args []string) error {
	var err error

	if glc.locale, err = i18n.LoadTranslations(); err != nil {
		return errors.Wrap(err, "loading translation files")
	}

	if _, err := os.Stat(glc.apiModelPath); os.IsNotExist(err) {
		return errors.Errorf("specified api-model does not exist (%s)", glc.apiModelPath)
	}

	if _, err := os.Stat(glc.sshPrivateKeyPath); os.IsNotExist(err) {
		return errors.Errorf("specified ssh-private-key does not exist (%s)", glc.sshPrivateKeyPath)
	}

	glc.location = helpers.NormalizeAzureRegion(glc.location)
	if glc.location == "" {
		return errors.New("--location must be specified")
	}

	if glc.outputDirectory == "" {
		glc.outputDirectory = path.Join(filepath.Dir(glc.apiModelPath), "_logs")
	}

	return nil
}

func (glc *getLogsCmd) loadAPIModel() error {
	var err error

	apiloader := &api.Apiloader{
		Translator: &i18n.Translator{
			Locale: glc.locale,
		},
	}

	// do not validate when initially loading the apimodel, validation is done later after autofilling values
	if glc.containerService, glc.apiVersion, err = apiloader.LoadContainerServiceFromFile(glc.apiModelPath, false, false, nil); err != nil {
		return errors.Wrap(err, "error parsing api-model")
	}

	if glc.containerService.Location == "" {
		glc.containerService.Location = glc.location
	} else if glc.containerService.Location != glc.location {
		return errors.New("--location flag does not match api-model location")
	}

	if glc.containerService.Properties.IsAzureStackCloud() {
		writeCustomCloudProfile(glc.containerService)
		if err = glc.containerService.Properties.SetAzureStackCloudSpec(api.AzureStackCloudSpecParams{}); err != nil {
			return errors.Wrap(err, "error parsing api-model")
		}
	}

	if err = glc.getAuthArgs().validateAuthArgs(); err != nil {
		return err
	}

	if glc.client, err = glc.authProvider.getClient(); err != nil {
		return errors.Wrap(err, "failed to get client")
	}

	return nil
}

func (glc *getLogsCmd) run(cmd *cobra.Command, args []string) error {
	var err error

	ctx, cancel := context.WithTimeout(context.Background(), armhelpers.DefaultARMOperationTimeout)
	defer cancel()

	if _, err = glc.client.EnsureResourceGroup(ctx, glc.resourceGroupName, glc.location, nil); err != nil {
		return errors.Wrap(err, "ensuring resource group")
	}

	if err = glc.getClusterNodes(); err != nil {
		return errors.Wrap(err, "listing cluster nodes")
	}

	log.Infoln("Collecting cluster logs")

	glc.setSSHConfig()
	err = glc.collectLogs()
	if err != nil {
		return errors.Wrap(err, "collecting logs")
	}

	// err = glc.writeArtifacts()
	// if err != nil {
	// 	return errors.Wrap(err, "writing artifacts")
	// }

	return nil
}

func (glc *getLogsCmd) collectLogs() error {
	collectLogsCmd := "sudo bash -c \"cat > /var/log/azure/logs.txt << EOL \n" + "HI THERE" + "EOL\""

	for _, host := range glc.masterNodes {
		log.Debugf("Ranging over node: %s\n", host.Name)
		for _, cmd := range []string{collectLogsCmd} {
			out, err := glc.sshCommandExecuter(cmd, glc.apiserver, host.Name, glc.sshConfig)
			if err != nil {
				log.Printf("Command %s output: %s\n", cmd, out)
				return errors.Wrap(err, "failed collecting")
			}
		}
	}

	for _, host := range glc.linuxNodes {
		log.Debugf("Ranging over node: %s\n", host.Name)
		for _, cmd := range []string{collectLogsCmd} {
			out, err := glc.sshCommandExecuter(cmd, glc.apiserver, host.Name, glc.sshConfig)
			if err != nil {
				log.Printf("Command %s output: %s\n", cmd, out)
				return errors.Wrap(err, "failed collecting")
			}
		}
	}

	// collectWindowsLogs := "execute c:\\k\\debug\\collect-windows-logs.ps1"
	// for _, host := range glc.windowsNodes {
	// 	log.Debugf("Ranging over node: %s\n", host.Name)
	// 	for _, cmd := range []string{collectWindowsLogs} {
	// 		out, err := glc.sshCommandExecuter(cmd, glc.apiserver, host.Name, "22", glc.sshConfig)
	// 		if err != nil {
	// 			log.Printf("Command %s output: %s\n", cmd, out)
	// 			return errors.Wrap(err, "failed collecting")
	// 		}
	// 	}
	// }

	return nil
}

// getClusterNodes copied from rotate-certs.go, TODO try to share it
func (glc *getLogsCmd) getClusterNodes() error {
	kubeClient, err := glc.getKubeClient()
	if err != nil {
		return errors.Wrap(err, "failed to get Kubernetes Client")
	}
	nodeList, err := kubeClient.ListNodes()
	if err != nil {
		return errors.Wrap(err, "failed to get cluster nodes")
	}
	for _, node := range nodeList.Items {
		if strings.Contains(node.Name, "master") {
			glc.masterNodes = append(glc.masterNodes, node)
		} else {
			// TODO handle windows nodes
			glc.linuxNodes = append(glc.linuxNodes, node)
		}
	}
	return nil
}

// getKubeClient copied from rotate-certs.go, TODO try to share it
func (glc *getLogsCmd) getKubeClient() (armhelpers.KubernetesClient, error) {
	kubeconfig, err := engine.GenerateKubeConfig(glc.containerService.Properties, glc.location)
	if err != nil {
		return nil, errors.Wrap(err, "generating kubeconfig")
	}

	if glc.client == nil {
		return nil, errors.Wrap(err, "AKSEngineClient was nil")
	}

	var kubeClient armhelpers.KubernetesClient
	if kubeClient, err = glc.client.GetKubernetesClient("", kubeconfig, time.Second*1, time.Duration(60)*time.Minute); err != nil {
		return nil, errors.Wrap(err, "failed to get a Kubernetes client")
	}
	return kubeClient, nil
}

// setSSHConfig copied from rotate-certs.go, TODO try to share it
func (glc *getLogsCmd) setSSHConfig() {
	glc.sshConfig = &ssh.ClientConfig{
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		User:            "azureuser",
		Auth: []ssh.AuthMethod{
			publicKeyFile(glc.sshPrivateKeyPath),
		},
	}
}

// executeRemoteCmd copied from rotate-certs.go, TODO try to share it
func executeRemoteCmd(command, apiserver, hostname string, config *ssh.ClientConfig) (string, error) {
	// Dial connection to the master via public load balancer
	lbClient, err := ssh.Dial("tcp", fmt.Sprintf("%s:%s", apiserver, "22"), config)
	if err != nil {
		return "", errors.Wrap(err, "dialing LB")
	}

	// Dial a connection to the agent host, from the master
	conn, err := lbClient.Dial("tcp", fmt.Sprintf("%s:22", hostname))
	if err != nil {
		return "", errors.Wrap(err, "dialing host")
	}

	ncc, chans, reqs, err := ssh.NewClientConn(conn, hostname, config)
	if err != nil {
		return "", errors.Wrap(err, "starting new client connection to host")
	}

	session, err := ssh.NewClient(ncc, chans, reqs).NewSession()
	if err != nil {
		return "", errors.Wrap(err, "opening SSH session")
	}
	defer session.Close()

	// var stdoutBuf bytes.Buffer
	// session.Stdout = &stdoutBuf
	// if err = session.Run(command); err != nil {
	// 	return fmt.Sprintf("%s -> %s", hostname, stdoutBuf.String()), errors.Wrap(err, "running command")
	// }

	// return fmt.Sprintf("%s -> %s", hostname, stdoutBuf.String()), nil

	r, err := session.StdoutPipe()
	if err != nil {
		return "", err
	}

	path := "/var/log/azure/logs.txt"
	file, err := os.OpenFile("logs.txt", os.O_WRONLY|os.O_CREATE, 0644)
	if err != nil {
		return "", err
	}
	defer file.Close()

	if err := session.Run(fmt.Sprintf("cat %s > /dev/stdout", path)); err != nil {
		return "", err
	}
	n, err := io.Copy(file, r)
	log.Debugf("Written: %x\n", n)

	if err != nil {
		return "", err
	}
	if err := session.Wait(); err != nil {
		return "", err
	}
	return "", err
}

// func (glc *getLogsCmd) writeArtifacts() error {
// 	ctx := engine.Context{
// 		Translator: &i18n.Translator{
// 			Locale: glc.locale,
// 		},
// 	}
// 	templateGenerator, err := engine.InitializeTemplateGenerator(ctx)
// 	if err != nil {
// 		return errors.Wrap(err, "initializing template generator")
// 	}
// 	template, parameters, err := templateGenerator.GenerateTemplateV2(glc.containerService, engine.DefaultGeneratorCode, BuildTag)
// 	if err != nil {
// 		return errors.Wrapf(err, "generating template %s", glc.apiModelPath)
// 	}

// 	if template, err = transform.PrettyPrintArmTemplate(template); err != nil {
// 		return errors.Wrap(err, "pretty-printing template")
// 	}
// 	if parameters, err = transform.BuildAzureParametersFile(parameters); err != nil {
// 		return errors.Wrap(err, "pretty-printing template parameters")
// 	}

// 	writer := &engine.ArtifactWriter{
// 		Translator: &i18n.Translator{
// 			Locale: glc.locale,
// 		},
// 	}
// 	return writer.WriteTLSArtifacts(glc.containerService, glc.apiVersion, template, parameters, glc.outputDirectory, true, false)
// }
