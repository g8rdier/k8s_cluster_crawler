# Übersicht für Cluster: fttc-tn01 (ingress)

| Namespace   | Name                                     | Hosts                                                                 | Adresse      | Ports           |
|:------------|:-----------------------------------------|:----------------------------------------------------------------------|:-------------|:----------------|
| gitlab-n01  | active-node                              | node.fttc-tn01.p72l9s.cluster.fits.cloud                              | 212.34.85.99 | 8080, 443, 8181 |
| gitlab-n01  | gitlab-prometheus-server-fttc-gitlab-n01 | gitlab-fttc-gitlab-n01-prometheus.fttc-tn01.p72l9s.cluster.fits.cloud | 212.34.85.99 | 80, 443         |
| gitlab-n01  | gitlab-registry                          | registry.fttc-tn01.p72l9s.cluster.fits.cloud                          | 212.34.85.5  | 5000, 443       |
| gitlab-n01  | gitlab-webservice-default                | git.fttc-tn01.p72l9s.cluster.fits.cloud                               | 212.34.85.5  | 443, 8181       |
| tempo       | ingress                                  | N/A                                                                   |              | 80              |
