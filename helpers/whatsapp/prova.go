package main

import (
	"fmt"
	"os"
	"time"

	"github.com/mdp/qrterminal/v3"
)

// Modo --prova: em vez de JSON, escreve para uma pessoa no terminal (QR desenhado, fase e contagens).
// Nunca imprime nome, número nem texto de mensagem: só quantidades.
var prova bool

// Em --prova, depois de conectar o ajudante espera o histórico chegar e sai sozinho, deixando a sessão guardada.
const esperaDoHistorico = 45 * time.Second

var encerrar = func() {}

func mostrarProva(v any) {
	switch m := v.(type) {
	case map[string]string:
		switch m["t"] {
		case "fase":
			if m["detalhe"] != "" {
				fmt.Printf("[%s] %s\n", m["fase"], m["detalhe"])
			} else {
				fmt.Printf("[%s]\n", m["fase"])
			}
			if m["fase"] == "conectado" {
				go func() { time.Sleep(esperaDoHistorico); encerrar() }()
			}
		case "qr":
			fmt.Println("\nWhatsApp no celular: Aparelhos conectados > Conectar um aparelho. Aponte para este QR:")
			fmt.Println()
			qrterminal.GenerateHalfBlock(m["codigo"], qrterminal.L, os.Stdout)
		}
	case map[string]any:
		if lista, ok := m["lista"].([]Conversa); ok {
			total := 0
			for _, c := range lista {
				total += c.NaoLidas
			}
			fmt.Printf("[conversas] %d com não lidas, %d não lidas no total\n", len(lista), total)
		}
	}
}
