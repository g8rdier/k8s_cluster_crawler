# Übersicht für Cluster: fttc-pf01 (ingress)

| Namespace         | Name                                 | Hosts                                                                                           | Adresse         | Ports           |
|:------------------|:-------------------------------------|:------------------------------------------------------------------------------------------------|:----------------|:----------------|
| doorman-fttc-p01  | cm-acme-http-solver-nlngr            | registry.p.fi-ts.io                                                                             | 212.34.85.226   | 8089            |
| doorman-fttc-p01  | cm-acme-http-solver-q275v            | dmauth.p.fi-ts.io                                                                               | 212.34.85.226   | 8089            |
| doorman-fttc-p01  | cm-acme-http-solver-rfdxr            | internal.p.fi-ts.io                                                                             | 212.34.85.226   | 8089            |
| doorman-fttc-p01  | cm-acme-http-solver-wbxhl            | git.p.fi-ts.io                                                                                  | 212.34.85.226   | 8089            |
| doorman-fttc-p01  | doorman                              | dmauth.fits.cloud, git.fits.cloud, registry.fits.cloud, *.pages.fits.cloud, internal.fits.cloud | 212.34.85.226   | 8000, 443       |
| fttc-gitlab-p01   | active-node                          | git.fits.cloud                                                                                  | 100.127.129.207 | 443, 8080       |
| fttc-gitlab-p01   | gitlab-gitlab-pages                  | *.pages.fits.cloud                                                                              | 100.127.129.207 | 443, 8090       |
| fttc-gitlab-p01   | gitlab-prometheus-server-fttc-p01    | gitlab-fttc-p01-prometheus.fits.cloud                                                           | 100.127.129.207 | 80, 443         |
| fttc-gitlab-p01   | gitlab-registry                      | registry.fits.cloud                                                                             | 100.127.129.207 | 5000, 443       |
| fttc-gitlab-p01   | gitlab-webservice-default            | git.fits.cloud                                                                                  | 100.127.129.207 | 443, 8181       |
| gitlab-wallis-p01 | active-node                          | sources.s-api.dev                                                                               | 100.127.129.207 | 443, 8080       |
| gitlab-wallis-p01 | gitlab-prometheus-server-wallis-p01  | gitlab-wallis-p01-prometheus.internal.s-api.dev                                                 | 100.127.129.207 | 80, 443         |
| gitlab-wallis-p01 | gitlab-registry                      | registry.s-api.dev                                                                              | 212.34.85.226   | 5000, 443       |
| gitlab-wallis-p01 | gitlab-webservice-default            | sources.s-api.dev                                                                               | 212.34.85.226   | 443, 8181       |
| iqs-fttc-p01      | p01-nexus-iq-server                  | artifacts-check.s-api.dev, admin-artifacts-check.s-api.dev                                      | 212.34.85.226   | 8071, 8070, 443 |
| nexus-wallis-p01  | nexus-repository-manager             | artifacts.s-api.dev                                                                             | 212.34.85.226   | 443, 8081       |
| nexus-wallis-p01  | nexus-repository-manager-docker-5000 | docker-artifacts.s-api.dev                                                                      | 212.34.85.226   | 5000, 443       |
| nexus-wallis-p01  | nexus-repository-manager-docker-5400 | images-devops.s-api.dev                                                                         | 212.34.85.226   | 5400, 443       |
| nexus-wallis-p01  | nexus-repository-manager-docker-5500 | images-dev.s-api.dev                                                                            | 212.34.85.226   | 5500, 443       |
| nexus-wallis-p01  | nexus-repository-manager-docker-5505 | images.s-api.dev                                                                                | 212.34.85.226   | 5505, 443       |
| nexus-wallis-p01  | nexus-repository-manager-docker-5600 | images-teams.s-api.dev                                                                          | 212.34.85.226   | 5600, 443       |
