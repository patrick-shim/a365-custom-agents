# MCR does not publish the repository's Visual Studio-serviced 10.0.110 SDK.
# Keep the container toolchain independently reproducible on a published SDK.
FROM mcr.microsoft.com/dotnet/sdk:10.0.302 AS build
WORKDIR /src

# Project paths follow the product namespace. A product rename must update this file and
# infra/README.md image commands in the same change.
COPY Directory.Build.props Directory.Packages.props ./
COPY server/agent/JapanExpert.Agent/JapanExpert.Agent.csproj server/agent/JapanExpert.Agent/
COPY server/agent-host/JapanExpert.AgentHost/JapanExpert.AgentHost.csproj server/agent-host/JapanExpert.AgentHost/

RUN dotnet restore server/agent-host/JapanExpert.AgentHost/JapanExpert.AgentHost.csproj

COPY server/agent/JapanExpert.Agent/ server/agent/JapanExpert.Agent/
COPY server/agent-host/JapanExpert.AgentHost/ server/agent-host/JapanExpert.AgentHost/

RUN dotnet publish server/agent-host/JapanExpert.AgentHost/JapanExpert.AgentHost.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_EnableDiagnostics=0

EXPOSE 8080

COPY --from=build /app/publish .

USER $APP_UID
ENTRYPOINT ["dotnet", "JapanExpert.AgentHost.dll"]
